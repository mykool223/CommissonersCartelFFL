// Sends one notification to every subscribed device.
//
// Called by an after-insert trigger (see 20260821000011_push_notifications.sql)
// rather than by the app, so a message notifies everyone regardless of which
// client wrote it — including rows I insert by hand.
//
// APNs wants a JWT signed ES256 with the .p8 key from the developer account.
// The key is a secret; the token derived from it is good for an hour, so it is
// cached rather than re-signed per device.

const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID")!;
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID")!;
const APNS_PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY");
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "com.commissionerscartel.app";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
// Used for the REST reads below. Supabase injects this and its format has
// changed once already (legacy JWT to sb_secret_), so it is never compared
// against anything — PUSH_SECRET below is what authenticates the caller.
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// Shared with the database trigger via Vault. A dedicated secret rather than
// the service role key, so rotating either one does not silently break the
// other.
const PUSH_SECRET = Deno.env.get("PUSH_SECRET")!;
// Firebase service account JSON, for Android. Absent until a Firebase project
// exists; Android devices are then skipped rather than the whole send failing.
const FCM_SERVICE_ACCOUNT = Deno.env.get("FCM_SERVICE_ACCOUNT");

/** Which preference column gates each kind of notification. */
const PREFERENCE_COLUMN: Record<string, string> = {
    messages: "messages",
    news: "news",
    polls: "polls",
};

/** The tab to open when the notification is tapped. */
const DESTINATION: Record<string, string> = {
    messages: "members",
    news: "news",
    polls: "polls",
};

function base64URL(bytes: Uint8Array): string {
    return btoa(String.fromCharCode(...bytes))
        .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Strips the PEM armour and decodes the PKCS#8 body Apple hands out. */
function decodePrivateKey(pem: string): Uint8Array {
    const body = pem
        .replace(/-----BEGIN PRIVATE KEY-----/, "")
        .replace(/-----END PRIVATE KEY-----/, "")
        .replace(/\s+/g, "");
    return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

let cached: { token: string; issuedAt: number } | null = null;

/**
 * APNs rejects a token younger than 20 minutes if you keep minting new ones,
 * and rejects one older than 60 minutes outright. Refreshing at 45 sits
 * safely between the two.
 */
async function providerToken(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    if (cached && now - cached.issuedAt < 45 * 60) return cached.token;

    const header = base64URL(
        new TextEncoder().encode(JSON.stringify({ alg: "ES256", kid: APNS_KEY_ID })),
    );
    const claims = base64URL(
        new TextEncoder().encode(JSON.stringify({ iss: APNS_TEAM_ID, iat: now })),
    );
    const unsigned = `${header}.${claims}`;

    const key = await crypto.subtle.importKey(
        "pkcs8",
        decodePrivateKey(APNS_PRIVATE_KEY),
        { name: "ECDSA", namedCurve: "P-256" },
        false,
        ["sign"],
    );
    const signature = new Uint8Array(
        await crypto.subtle.sign(
            { name: "ECDSA", hash: "SHA-256" },
            key,
            new TextEncoder().encode(unsigned),
        ),
    );

    const token = `${unsigned}.${base64URL(signature)}`;
    cached = { token, issuedAt: now };
    return token;
}

interface DeviceRow {
    token: string;
    user_id: string;
    environment: "sandbox" | "production";
    platform: "ios" | "android";
}

async function subscribedDevices(kind: string, excludeUser: string | null): Promise<DeviceRow[]> {
    const rest = async (path: string) => {
        const response = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
            headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
        });
        if (!response.ok) throw new Error(`${path}: ${response.status} ${await response.text()}`);
        return await response.json();
    };

    const devices: DeviceRow[] = await rest(
        "device_tokens?select=token,user_id,environment,platform",
    );
    const column = PREFERENCE_COLUMN[kind];

    // Only users who explicitly turned this kind off are excluded. Someone who
    // has never opened Settings has no preferences row and stays subscribed.
    const muted: { user_id: string }[] = await rest(
        `notification_preferences?select=user_id&${column}=is.false`,
    );
    const mutedIDs = new Set(muted.map((row) => row.user_id));

    return devices.filter((device) =>
        device.user_id !== excludeUser && !mutedIDs.has(device.user_id)
    );
}

/** A token APNs reports as dead is worth deleting; it will never work again. */
async function forgetToken(token: string): Promise<void> {
    await fetch(`${SUPABASE_URL}/rest/v1/device_tokens?token=eq.${encodeURIComponent(token)}`, {
        method: "DELETE",
        headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
    });
}

async function sendAPNs(device: DeviceRow, payload: unknown, jwt: string): Promise<string> {
    const host = device.environment === "sandbox"
        ? "api.sandbox.push.apple.com"
        : "api.push.apple.com";

    const response = await fetch(`https://${host}/3/device/${device.token}`, {
        method: "POST",
        headers: {
            authorization: `bearer ${jwt}`,
            "apns-topic": APNS_BUNDLE_ID,
            "apns-push-type": "alert",
            "apns-priority": "10",
        },
        body: JSON.stringify(payload),
    });

    if (response.ok) return "sent";

    const detail = await response.text();
    // 410 Gone means the app was deleted. 400 BadDeviceToken usually means the
    // token belongs to the other APNs environment than the one recorded.
    if (response.status === 410 || detail.includes("BadDeviceToken")) {
        await forgetToken(device.token);
        return "pruned";
    }
    console.error(`APNs ${response.status} for ${device.token.slice(0, 8)}…: ${detail}`);
    return "failed";
}

/**
 * Firebase wants an OAuth access token, obtained by signing a JWT with the
 * service account's RSA key — a different algorithm and a different exchange
 * from Apple's, which is why none of the APNs code above is reused.
 */
let cachedGoogle: { token: string; expiresAt: number } | null = null;

async function googleAccessToken(): Promise<string | null> {
    if (!FCM_SERVICE_ACCOUNT) return null;

    const now = Math.floor(Date.now() / 1000);
    if (cachedGoogle && now < cachedGoogle.expiresAt - 300) return cachedGoogle.token;

    const account = JSON.parse(FCM_SERVICE_ACCOUNT);
    const header = base64URL(
        new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })),
    );
    const claims = base64URL(new TextEncoder().encode(JSON.stringify({
        iss: account.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 3600,
    })));
    const unsigned = `${header}.${claims}`;

    const key = await crypto.subtle.importKey(
        "pkcs8",
        decodePrivateKey(account.private_key),
        { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
        false,
        ["sign"],
    );
    const signature = new Uint8Array(
        await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)),
    );

    const response = await fetch("https://oauth2.googleapis.com/token", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
            grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
            assertion: `${unsigned}.${base64URL(signature)}`,
        }),
    });
    if (!response.ok) {
        console.error(`Google token exchange failed: ${await response.text()}`);
        return null;
    }

    const { access_token, expires_in } = await response.json();
    cachedGoogle = { token: access_token, expiresAt: now + expires_in };
    return access_token;
}

async function sendFCM(
    device: DeviceRow,
    title: string,
    body: string,
    destination: string,
    accessToken: string,
    projectID: string,
): Promise<string> {
    const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectID}/messages:send`,
        {
            method: "POST",
            headers: {
                Authorization: `Bearer ${accessToken}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                message: {
                    token: device.token,
                    notification: { title, body },
                    // Read by the Android client to open the right tab, the
                    // same job `destination` does in the APNs payload.
                    data: { destination },
                    android: { priority: "high" },
                },
            }),
        },
    );

    if (response.ok) return "sent";

    const detail = await response.text();
    // UNREGISTERED means the app was uninstalled; INVALID_ARGUMENT on a token
    // means it was never valid. Neither will ever work again.
    if (response.status === 404 || detail.includes("UNREGISTERED") ||
        detail.includes("INVALID_ARGUMENT")) {
        await forgetToken(device.token);
        return "pruned";
    }
    console.error(`FCM ${response.status} for ${device.token.slice(0, 8)}…: ${detail}`);
    return "failed";
}

Deno.serve(async (request) => {
    // verify_jwt is off for this function, so this check is the only thing
    // standing between the open internet and a push to twelve phones.
    const authorization = request.headers.get("Authorization") ?? "";
    if (!PUSH_SECRET || authorization !== `Bearer ${PUSH_SECRET}`) {
        return new Response("Forbidden", { status: 403 });
    }

    try {
        return await handle(request);
    } catch (error) {
        // Without this any throw surfaces as an opaque 500 in
        // net._http_response, with nothing to debug from.
        const message = error instanceof Error ? error.stack ?? error.message : String(error);
        console.error(`push failed: ${message}`);
        return new Response(message, { status: 500 });
    }
});

async function handle(request: Request): Promise<Response> {
    const { kind, title, body, exclude_user } = await request.json();
    if (!PREFERENCE_COLUMN[kind]) {
        return new Response(`Unknown kind: ${kind}`, { status: 400 });
    }

    const devices = await subscribedDevices(kind, exclude_user ?? null);
    if (devices.length === 0) {
        return Response.json({ sent: 0, pruned: 0, failed: 0 });
    }

    const destination = DESTINATION[kind];
    const apple = devices.filter((device) => device.platform === "ios");
    const google = devices.filter((device) => device.platform === "android");

    const work: Promise<string>[] = [];

    // Same shape as the Android branch below: missing credentials must skip
    // that platform, not fail the whole send. Push is configured one platform
    // at a time, so there is always a window where only one is ready.
    if (apple.length > 0 && !APNS_PRIVATE_KEY) {
        console.warn(`Skipping ${apple.length} Apple device(s): APNs is not configured.`);
    } else if (apple.length > 0) {
        const payload = {
            aps: {
                alert: { title, body },
                sound: "default",
                "thread-id": kind,
            },
            destination,
        };
        const jwt = await providerToken();
        work.push(...apple.map((device) => sendAPNs(device, payload, jwt)));
    }

    if (google.length > 0) {
        const accessToken = await googleAccessToken();
        if (accessToken) {
            const projectID = JSON.parse(FCM_SERVICE_ACCOUNT!).project_id;
            work.push(...google.map((device) =>
                sendFCM(device, title, body, destination, accessToken, projectID)
            ));
        } else {
            // No Firebase credentials yet. Say so rather than reporting these
            // as failures, which would look like a delivery problem.
            console.warn(`Skipping ${google.length} Android device(s): FCM is not configured.`);
        }
    }

    const results = await Promise.all(work);

    return Response.json({
        sent: results.filter((r) => r === "sent").length,
        pruned: results.filter((r) => r === "pruned").length,
        failed: results.filter((r) => r === "failed").length,
    });
}
