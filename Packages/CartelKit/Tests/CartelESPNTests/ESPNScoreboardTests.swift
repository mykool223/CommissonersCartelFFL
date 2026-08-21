import Foundation
import Testing
import CartelCore
@testable import CartelESPN

@Suite("NFL scoreboard")
struct ESPNScoreboardTests {
    private func client(
        statusCode: Int = 200,
        now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 0) },
        onRequest: (@Sendable (URLRequest) -> Void)? = nil
    ) throws -> ESPNScoreboardClient {
        let url = try #require(
            Bundle.module.url(forResource: "scoreboard", withExtension: "json")
        )
        let data = statusCode == 200 ? try Data(contentsOf: url) : Data("{}".utf8)
        return ESPNScoreboardClient(
            transport: StubTransport { request in
                onRequest?(request)
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil
                )!
                return (data, response)
            },
            now: now
        )
    }

    @Test("Week and season type map across")
    func weekAndSeason() async throws {
        let board = try await client().scoreboard()
        #expect(board.seasonYear == 2026)
        #expect(board.week == 3)
        #expect(board.isPreseason)
        #expect(board.weekTitle == "Preseason Week 3")
        #expect(board.games.count == 3)
    }

    @Test("All three game states are recognised")
    func states() async throws {
        let games = try await client().scoreboard().games
        #expect(games.contains { $0.state == .scheduled })
        #expect(games.contains { $0.state == .inProgress })
        #expect(games.contains { $0.state == .final })
    }

    /// ESPN sends "0" for both sides before kickoff. Rendered literally that is
    /// a 0-0 scoreline for a game nobody has played.
    @Test("An unplayed game has no score, rather than 0-0")
    func scheduledHasNoScore() async throws {
        let games = try await client().scoreboard().games
        let upcoming = try #require(games.first { $0.state == .scheduled })
        #expect(upcoming.home.score == nil)
        #expect(upcoming.away.score == nil)
        #expect(upcoming.period == nil, "no period before kickoff")
        #expect(upcoming.leadingAbbreviation == nil)
    }

    @Test("A live game carries period, clock and scores")
    func liveGame() async throws {
        let games = try await client().scoreboard().games
        let live = try #require(games.first { $0.state == .inProgress })
        #expect(live.period == 3)
        #expect(live.clock == "5:42")
        #expect(live.home.score == 17)
        #expect(live.away.score == 24)
        #expect(live.leadingAbbreviation == live.away.abbreviation)
    }

    @Test("A finished game keeps its score but drops the clock")
    func finalGame() async throws {
        let games = try await client().scoreboard().games
        let done = try #require(games.first { $0.state == .final })
        #expect(done.home.score != nil)
        #expect(done.clock == nil, "a finished game has no running clock")
        #expect(done.statusDetail == "Final")
    }

    /// ESPN's timestamps omit the seconds field. Parsed with the stock
    /// ISO-8601 style they all fail, and the fallback rendered as the same
    /// plausible-looking kickoff time on every single game.
    @Test("Every game has a real kickoff time")
    func kickoffTimesParse() async throws {
        let games = try await client().scoreboard().games
        #expect(games.allSatisfy { $0.startDate != nil })

        let upcoming = try #require(games.first { $0.state == .scheduled })
        let start = try #require(upcoming.startDate)
        #expect(start.timeIntervalSince1970 == 1_787_353_200)
    }

    @Test("Games do not all share one timestamp")
    func timesAreDistinct() async throws {
        let games = try await client().scoreboard().games
        let stamps = Set(games.compactMap { $0.startDate })
        #expect(stamps.count > 1, "identical timestamps mean parsing fell back")
    }

    @Test("Teams carry a raster logo, unlike the fantasy API's SVGs")
    func logos() async throws {
        let games = try await client().scoreboard().games
        let game = try #require(games.first)
        let logo = try #require(game.home.logoURL)
        #expect(logo.pathExtension == "png")
    }

    @Test("Live games sort ahead of upcoming, and finished games last")
    func readingOrder() async throws {
        let board = try await client().scoreboard()
        let order = board.gamesInReadingOrder.map(\.state)
        #expect(order.first == .inProgress)
        #expect(order.last == .final)
        #expect(board.hasLiveGames)
    }

    @Test("The scoreboard is cached, and refresh clears it")
    func caching() async throws {
        let counter = Counter()
        let client = try client(onRequest: { _ in counter.increment() })

        _ = try await client.scoreboard()
        _ = try await client.scoreboard()
        #expect(counter.value == 1)

        await client.refresh()
        _ = try await client.scoreboard()
        #expect(counter.value == 2)
    }

    @Test("A server error surfaces rather than showing an empty board")
    func serverError() async throws {
        let client = try client(statusCode: 503)
        await #expect(throws: CartelError.self) { _ = try await client.scoreboard() }
    }

    @Test("The scoreboard needs no credentials")
    func noCredentialsSent() async throws {
        let captured = Captured()
        _ = try await client(onRequest: { captured.store($0) }).scoreboard()
        let request = try #require(captured.value)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    /// Local to this file: the one in ESPNClientTests is fileprivate.
    private final class Captured: @unchecked Sendable {
        private let lock = NSLock()
        private var request: URLRequest?
        func store(_ request: URLRequest) {
            lock.lock(); defer { lock.unlock() }
            self.request = request
        }
        var value: URLRequest? {
            lock.lock(); defer { lock.unlock() }
            return request
        }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }
}
