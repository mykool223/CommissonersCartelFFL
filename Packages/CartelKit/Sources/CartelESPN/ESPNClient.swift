import Foundation
import CartelCore

/// `LeagueDataSource` backed by ESPN's fantasy v3 endpoints.
///
/// One request returns teams, members, settings and the full schedule, so the
/// client fetches that single payload and serves all four protocol methods from
/// it. An actor guarantees that N concurrent screens appearing at once produce
/// one network call, not N.
public actor ESPNClient: LeagueDataSource {
    private let configuration: ESPNConfiguration
    private let transport: HTTPTransport
    /// Injected so tests can control cache expiry without sleeping.
    private let now: @Sendable () -> Date

    private var cached: (response: ESPNLeagueResponse, fetchedAt: Date)?
    /// In-flight request, so concurrent callers await one fetch instead of racing.
    private var inFlight: Task<ESPNLeagueResponse, Error>?

    /// The views that together cover every screen in the app.
    private static let views = [
        "mSettings",   // league name, schedule length
        "mTeam",       // team names, logos, owners, records
        "mMatchupScore", // weekly scores
    ]

    public init(
        configuration: ESPNConfiguration,
        transport: HTTPTransport = URLSessionTransport(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.transport = transport
        self.now = now
    }

    // MARK: - LeagueDataSource

    public func league() async throws -> League {
        ESPNMapper.league(from: try await payload(), fallbackSeason: configuration.season)
    }

    public func managers() async throws -> [Manager] {
        ESPNMapper.managers(from: try await payload())
    }

    public func teams() async throws -> [Team] {
        ESPNMapper.teams(
            from: try await payload(),
            imageProxyBase: configuration.imageProxyBase
        )
    }

    public func matchups(week: Int) async throws -> [Matchup] {
        ESPNMapper.matchups(from: try await payload(), week: week)
    }

    /// Drops the cache so the next call hits the network. Wire this to
    /// pull-to-refresh.
    public func invalidateCache() {
        cached = nil
    }

    public func refresh() async {
        invalidateCache()
    }

    // MARK: - Fetching

    private func payload() async throws -> ESPNLeagueResponse {
        if let cached, now().timeIntervalSince(cached.fetchedAt) < configuration.cacheTTL.seconds {
            return cached.response
        }
        if let inFlight { return try await inFlight.value }

        let task = Task { try await fetch() }
        inFlight = task
        defer { inFlight = nil }

        let response = try await task.value
        cached = (response, now())
        return response
    }

    private func fetch() async throws -> ESPNLeagueResponse {
        guard !configuration.leagueID.isEmpty else {
            throw CartelError.notConfigured("No ESPN league id is set.")
        }
        guard let url = configuration.requestURL(views: Self.views) else {
            throw CartelError.notConfigured("Could not build the ESPN request URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let credentials = configuration.credentials {
            request.setValue(credentials.cookieHeader, forHTTPHeaderField: "Cookie")
        }
        for (field, value) in configuration.additionalHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response) = try await transport.send(request)

        switch response.statusCode {
        case 200...299:
            break
        case 401, 403:
            // ESPN returns these for private leagues with missing or stale cookies.
            throw CartelError.notAuthorized
        default:
            throw CartelError.server(
                statusCode: response.statusCode,
                message: String(data: data.prefix(500), encoding: .utf8)
            )
        }

        do {
            return try JSONDecoder().decode(ESPNLeagueResponse.self, from: data)
        } catch {
            throw CartelError.decoding(
                "ESPN's payload didn't match what we expected — they may have changed it. \(error)"
            )
        }
    }
}

private extension Duration {
    /// Seconds as a Double, for comparing against `TimeInterval`.
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}
