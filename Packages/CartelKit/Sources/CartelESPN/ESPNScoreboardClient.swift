import Foundation
import CartelCore

/// Live NFL scores from ESPN's public scoreboard endpoint.
///
/// A different API from the fantasy one: no cookies, no league id, no proxy —
/// it is the feed espn.com's own scoreboard runs on. Because it needs no
/// credentials, the app talks to it directly.
public actor ESPNScoreboardClient: NFLScoreboardSource {
    private let url: URL
    private let transport: HTTPTransport
    /// Short, because the point is live scores. Long enough that flipping
    /// between sections does not re-request on every tap.
    private let cacheTTL: Duration
    private let now: @Sendable () -> Date

    private var cached: (scoreboard: NFLScoreboard, fetchedAt: Date)?
    private var inFlight: Task<NFLScoreboard, Error>?

    public static let defaultURL = URL(
        string: "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard"
    )!

    public init(
        url: URL = ESPNScoreboardClient.defaultURL,
        transport: HTTPTransport = URLSessionTransport(),
        cacheTTL: Duration = .seconds(30),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.url = url
        self.transport = transport
        self.cacheTTL = cacheTTL
        self.now = now
    }

    public func scoreboard() async throws -> NFLScoreboard {
        if let cached, now().timeIntervalSince(cached.fetchedAt) < cacheTTL.seconds {
            return cached.scoreboard
        }
        if let inFlight { return try await inFlight.value }

        let task = Task { try await fetch() }
        inFlight = task
        defer { inFlight = nil }

        let scoreboard = try await task.value
        cached = (scoreboard, now())
        return scoreboard
    }

    public func refresh() async {
        cached = nil
    }

    private func fetch() async throws -> NFLScoreboard {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // ESPN's edge rejects the default URLSession agent — which identifies
        // this app — with an HTML "Access Denied" page, and allows known HTTP
        // clients through. Without this the scoreboard fails to decode.
        request.setValue("curl/8.7.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await transport.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw CartelError.server(
                statusCode: response.statusCode,
                message: String(data: data.prefix(300), encoding: .utf8)
            )
        }

        do {
            return ESPNScoreboardMapper.scoreboard(
                from: try JSONDecoder().decode(ESPNScoreboardResponse.self, from: data)
            )
        } catch {
            throw CartelError.decoding("ESPN's scoreboard didn't match what we expected. \(error)")
        }
    }
}

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}
