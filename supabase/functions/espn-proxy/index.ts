// Forwards read-only ESPN fantasy requests, holding the session cookies as a
// server-side secret.
//
// Why this exists: a private ESPN league needs `espn_s2` and `SWID` cookies,
// which are credentials for a real ESPN account. Shipping them inside the iOS
// app means anyone who downloads the binary can extract them. Here they live in
// Supabase's secret store and never leave the server.
//
// Deploy:
//   supabase secrets set ESPN_S2=... ESPN_SWID='{...}'
//   supabase functions deploy espn-proxy
//
// Point the app at it with `ESPNConfiguration.viaProxy(...)`. The path shape
// matches ESPN's exactly, so nothing else in the client changes.

const ESPN_HOST = "https://lm-api-reads.fantasy.espn.com";

// The request path is anchored on ESPN's own "/apis/" segment rather than by
// stripping a known prefix. Supabase strips "/functions/v1" before invoking, so
// the function actually sees "/espn-proxy/apis/...", and hardcoding the full
// public prefix silently rejects every request as "Path not allowed".
const ESPN_PATH_MARKER = "/apis/";

// Only the read endpoints the app actually uses. Without this the function
// would be an open relay to any ESPN URL an attacker chose.
const ALLOWED_PATH = /^\/apis\/v3\/games\/ffl\/seasons\/\d{4}\/segments\/0\/leagues\/\d+$/;

// Uploaded team logos. ESPN serves these from a different host and returns 401
// without session cookies, so the app cannot fetch them directly. Stock logos
// come from the public CDN and never reach this function.
const ALLOWED_IMAGE_PATH =
  /^\/apis\/v1\/domains\/lm\/images\/[A-Za-z0-9-]+$/;
const ESPN_IMAGE_HOST = "https://mystique-api.fantasy.espn.com";

const ALLOWED_VIEWS = new Set([
  "mSettings",
  "mTeam",
  "mRoster",
  "mMatchup",
  "mMatchupScore",
  "mStandings",
  "mBoxscore",
]);

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

/// Reads the `role` claim without verifying the signature — Supabase already
/// verified it before this function ran, so re-checking here would be theatre.
function jwtRole(authorization: string): string | null {
  const token = authorization.replace(/^Bearer\s+/i, "");
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    const payload = JSON.parse(
      atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")),
    );
    return typeof payload.role === "string" ? payload.role : null;
  } catch {
    return null;
  }
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (request.method !== "GET") {
    return json({ message: "Only GET is supported." }, 405);
  }

  // Supabase verifies the JWT before invoking this function (verify_jwt is on
  // by default). This check is a guard against that being switched off.
  const authorization = request.headers.get("Authorization");
  if (!authorization) {
    return json({ message: "Missing Authorization header." }, 401);
  }

  // The anon key is a valid JWT and ships inside the app, so by default anyone
  // holding it can read the league through here. That is still a large net win
  // over shipping ESPN session cookies in the binary, but it is not the end
  // state.
  //
  // Once sign-in exists, tighten it without touching this code:
  //   supabase secrets set ESPN_PROXY_REQUIRE_AUTH=true
  //
  // after which only signed-in league members get through.
  const requireAuthenticated =
    (Deno.env.get("ESPN_PROXY_REQUIRE_AUTH") ?? "false").toLowerCase() === "true";
  const role = jwtRole(authorization);

  if (requireAuthenticated && role !== "authenticated") {
    return json(
      { message: "Sign in to view the league.", role },
      403,
    );
  }

  const url = new URL(request.url);
  const markerIndex = url.pathname.indexOf(ESPN_PATH_MARKER);
  const path = markerIndex >= 0
    ? url.pathname.slice(markerIndex)
    : url.pathname;

  const isImage = ALLOWED_IMAGE_PATH.test(path);

  if (!isImage && !ALLOWED_PATH.test(path)) {
    return json({ message: `Path not allowed: ${path}` }, 400);
  }

  const views = url.searchParams.getAll("view");
  if (views.some((view) => !ALLOWED_VIEWS.has(view))) {
    return json({ message: "Unsupported view parameter." }, 400);
  }

  const espnS2 = Deno.env.get("ESPN_S2");
  const swid = Deno.env.get("ESPN_SWID");

  const headers: Record<string, string> = { Accept: "application/json" };
  if (espnS2 && swid) {
    const wrapped = swid.startsWith("{") ? swid : `{${swid}}`;
    headers.Cookie = `espn_s2=${espnS2}; SWID=${wrapped}`;
  }
  // No secrets configured is fine for a public league — just forward without.

  const target = new URL((isImage ? ESPN_IMAGE_HOST : ESPN_HOST) + path);
  for (const view of views) {
    target.searchParams.append("view", view);
  }

  let upstream: Response;
  try {
    upstream = await fetch(target, { headers });
  } catch (error) {
    return json({ message: `Could not reach ESPN: ${error}` }, 502);
  }

  // Images are binary, so they must not go through .text().
  if (isImage) {
    return new Response(upstream.body, {
      status: upstream.status,
      headers: {
        ...CORS_HEADERS,
        "Content-Type": upstream.headers.get("Content-Type") ?? "image/jpeg",
        // Logos change rarely; a day of caching keeps them off ESPN entirely.
        "Cache-Control": "public, max-age=86400",
      },
    });
  }

  const body = await upstream.text();

  // Pass ESPN's status through so the client's 401 -> "check your credentials"
  // handling still works.
  return new Response(body, {
    status: upstream.status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json",
      // One minute of edge caching, well inside ESPN's rate limits.
      "Cache-Control": "public, max-age=60",
    },
  });
});
