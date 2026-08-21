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
const APNS_PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY")!;
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
}

async function subscribedDevices(kind: string, excludeUser: string | null): Promise<DeviceRow[]> {
    const rest = async (path: string) => {
        const response = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
            headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
        });
        if (!response.ok) throw new Error(`${path}: ${response.status} ${await response.text()}`);
        return await response.json();
    };

    const devices: DeviceRow[] = await rest("device_tokens?select=token,user_id,environment");
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

async function send(device: DeviceRow, payload: unknown, jwt: string): Promise<string> {
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

Deno.serve(async (request) => {
    // verify_jwt is off for this function, so this check is the only thing
    // standing between the open internet and a push to twelve phones.
    const authorization = request.headers.get("Authorization") ?? "";
    if (!PUSH_SECRET || authorization !== `Bearer ${PUSH_SECRET}`) {
        return new Response("Forbidden", { status: 403 });
    }

    const { kind, title, body, exclude_user } = await request.json();
    if (!PREFERENCE_COLUMN[kind]) {
        return new Response(`Unknown kind: ${kind}`, { status: 400 });
    }

    const devices = await subscribedDevices(kind, exclude_user ?? null);
    if (devices.length === 0) {
        return Response.json({ sent: 0, pruned: 0, failed: 0 });
    }

    const payload = {
        aps: {
            alert: { title, body },
            sound: "default",
            "thread-id": kind,
        },
        destination: DESTINATION[kind],
    };

    const jwt = await providerToken();
    const results = await Promise.all(devices.map((device) => send(device, payload, jwt)));

    return Response.json({
        sent: results.filter((r) => r === "sent").length,
        pruned: results.filter((r) => r === "pruned").length,
        failed: results.filter((r) => r === "failed").length,
    });
});
