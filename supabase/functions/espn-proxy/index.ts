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
const PROXY_PREFIX = "/functions/v1/espn-proxy";

// Only the read endpoints the app actually uses. Without this the function
// would be an open relay to any ESPN URL an attacker chose.
const ALLOWED_PATH = /^\/apis\/v3\/games\/ffl\/seasons\/\d{4}\/segments\/0\/leagues\/\d+$/;

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
  if (!request.headers.get("Authorization")) {
    return json({ message: "Missing Authorization header." }, 401);
  }

  const url = new URL(request.url);
  const path = url.pathname.startsWith(PROXY_PREFIX)
    ? url.pathname.slice(PROXY_PREFIX.length)
    : url.pathname;

  if (!ALLOWED_PATH.test(path)) {
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

  const target = new URL(ESPN_HOST + path);
  for (const view of views) {
    target.searchParams.append("view", view);
  }

  let upstream: Response;
  try {
    upstream = await fetch(target, { headers });
  } catch (error) {
    return json({ message: `Could not reach ESPN: ${error}` }, 502);
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
