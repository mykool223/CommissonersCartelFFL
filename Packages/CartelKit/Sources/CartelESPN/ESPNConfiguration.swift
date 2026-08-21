import Foundation

/// Credentials for a private ESPN league.
///
/// These are ESPN *session cookies for a real account*, not an API key. Treat
/// them like a password: never commit them, and prefer routing requests
/// through the `espn-proxy` Supabase function so they never ship inside the
/// app binary at all. See docs/ESPN_API.md.
public struct ESPNCredentials: Hashable, Sendable {
    public let espnS2: String
    public let swid: String

    public init(espnS2: String, swid: String) {
        // Copy-pasting out of developer tools drags in whitespace and newlines.
        self.espnS2 = espnS2.trimmingCharacters(in: .whitespacesAndNewlines)

        var cleaned = swid.trimmingCharacters(in: .whitespacesAndNewlines)

        // Some browsers show the SWID percent-encoded (%7B...%7D) rather than
        // as literal braces. Decoding first means the brace check below sees
        // the real value instead of wrapping an already-wrapped id.
        if cleaned.localizedCaseInsensitiveContains("%7B"),
           let decoded = cleaned.removingPercentEncoding {
            cleaned = decoded
        }

        // ESPN expects the SWID wrapped in braces; accept it either way.
        self.swid = cleaned.hasPrefix("{") ? cleaned : "{\(cleaned)}"
    }

    var cookieHeader: String {
        "espn_s2=\(espnS2); SWID=\(swid)"
    }
}

public struct ESPNConfiguration: Sendable {
    /// The numeric id from the league URL: `.../leagueId=XXXXXXX`.
    public let leagueID: String
    public let season: Int
    /// Nil for public leagues.
    public let credentials: ESPNCredentials?
    /// How long a fetched league payload stays fresh. ESPN rate-limits
    /// aggressively, and one payload feeds every screen, so this is deliberately
    /// not tiny.
    public let cacheTTL: Duration
    public let baseURL: URL

    /// Sent on every request. Used to pass a Supabase `Authorization` header
    /// when `baseURL` points at the `espn-proxy` edge function instead of ESPN.
    public let additionalHeaders: [String: String]

    /// Base for rewriting cookie-protected team logos. Nil when talking to ESPN
    /// directly, since the app has no way to authenticate an image request.
    public let imageProxyBase: URL?

    /// The read-optimised host ESPN's own web client uses. The older
    /// `fantasy.espn.com` host still works but is slower and rate-limited harder.
    public static let defaultBaseURL = URL(string: "https://lm-api-reads.fantasy.espn.com")!

    public init(
        leagueID: String,
        season: Int,
        credentials: ESPNCredentials? = nil,
        cacheTTL: Duration = .seconds(120),
        baseURL: URL = ESPNConfiguration.defaultBaseURL,
        additionalHeaders: [String: String] = [:],
        imageProxyBase: URL? = nil
    ) {
        self.leagueID = leagueID
        self.season = season
        self.credentials = credentials
        self.cacheTTL = cacheTTL
        self.baseURL = baseURL
        self.additionalHeaders = additionalHeaders
        self.imageProxyBase = imageProxyBase
    }

    /// Routes requests through the `espn-proxy` edge function, which holds the
    /// ESPN cookies as a server-side secret so they never ship in the app.
    /// The proxy preserves ESPN's path shape, so only the base URL changes.
    public static func viaProxy(
        leagueID: String,
        season: Int,
        supabaseURL: URL,
        accessToken: String,
        cacheTTL: Duration = .seconds(120)
    ) -> ESPNConfiguration {
        ESPNConfiguration(
            leagueID: leagueID,
            season: season,
            credentials: nil,
            cacheTTL: cacheTTL,
            baseURL: supabaseURL.appending(path: "/functions/v1/espn-proxy"),
            additionalHeaders: ["Authorization": "Bearer \(accessToken)"],
            // Uploaded logos 401 without ESPN cookies, so they go through the
            // same function. Fetching them needs the same Authorization header
            // as any other call, which is why the app loads logos with
            // URLSession rather than AsyncImage — AsyncImage cannot set headers,
            // and Supabase rejects the request before the function ever runs.
            imageProxyBase: supabaseURL.appending(path: "/functions/v1/espn-proxy")
        )
    }

    /// `/apis/v3/games/ffl/seasons/{season}/segments/0/leagues/{id}?view=...`
    ///
    /// The views are repeated query items, which is what ESPN expects; a
    /// comma-joined single `view` param returns a partial payload.
    func requestURL(views: [String]) -> URL? {
        var components = URLComponents(
            url: baseURL.appending(
                path: "/apis/v3/games/ffl/seasons/\(season)/segments/0/leagues/\(leagueID)"
            ),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = views.map { URLQueryItem(name: "view", value: $0) }
        return components?.url
    }
}
