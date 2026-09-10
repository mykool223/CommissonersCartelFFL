import Foundation
import Testing
import CartelCore
@testable import CartelESPN

private enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json"),
            "Missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }
}

private func makeClient(
    fixture: String = "league",
    statusCode: Int = 200,
    credentials: ESPNCredentials? = nil,
    cacheTTL: Duration = .seconds(120),
    now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 0) },
    onRequest: (@Sendable (URLRequest) -> Void)? = nil
) throws -> ESPNClient {
    let data = statusCode == 200 ? try Fixture.data(fixture) : Data("{}".utf8)
    let transport = StubTransport { request in
        onRequest?(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil
        )!
        return (data, response)
    }
    return ESPNClient(
        configuration: ESPNConfiguration(
            leagueID: "1234567",
            season: 2025,
            credentials: credentials,
            cacheTTL: cacheTTL
        ),
        transport: transport,
        now: now
    )
}

private func clientOverPayload(_ json: String) -> ESPNClient {
    let transport = StubTransport { request in
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        return (Data(json.utf8), response)
    }
    return ESPNClient(
        configuration: ESPNConfiguration(leagueID: "1234567", season: 2026),
        transport: transport,
        now: { Date(timeIntervalSince1970: 0) }
    )
}

@Suite("Live scoring")
struct ESPNLiveScoringTests {
    /// ESPN keeps totalPoints at 0.0 for the whole week it is being played and
    /// puts the running score in totalPointsLive. Reading only the former left
    /// the scoreboard on dashes every Sunday, filling in once everything was
    /// over — the one moment nobody needed it.
    private static let inProgress = """
    {
      "id": 1234567,
      "schedule": [{
        "id": 1, "matchupPeriodId": 1, "winner": "UNDECIDED",
        "home": {"teamId": 10, "totalPoints": 0.0, "totalPointsLive": 14.2,
                 "totalProjectedPointsLive": 116.5},
        "away": {"teamId": 7, "totalPoints": 0.0, "totalPointsLive": 6.0,
                 "totalProjectedPointsLive": 121.3}
      }]
    }
    """

    /// Once the period is settled totalPoints is the authority: ESPN stops
    /// updating totalPointsLive, and on a corrected stat the two disagree.
    private static let finished = """
    {
      "id": 1234567,
      "schedule": [{
        "id": 1, "matchupPeriodId": 1, "winner": "HOME",
        "home": {"teamId": 10, "totalPoints": 128.4, "totalPointsLive": 126.9},
        "away": {"teamId": 7, "totalPoints": 121.7, "totalPointsLive": 119.0}
      }]
    }
    """

    @Test("A week in progress shows the running score, not zero")
    func liveScore() async throws {
        let matchups = try await clientOverPayload(Self.inProgress).matchups(week: 1)
        let game = try #require(matchups.first)

        #expect(game.home.points == 14.2)
        #expect(game.away?.points == 6.0)
        #expect(!game.isComplete)
        // The status chip keys off points, so this is what stops a live board
        // still calling itself "scheduled".
        #expect(game.hasStarted)
    }

    @Test("A settled week uses the final total, not the last live one")
    func finalScore() async throws {
        let matchups = try await clientOverPayload(Self.finished).matchups(week: 1)
        let game = try #require(matchups.first)

        #expect(game.isComplete)
        #expect(game.home.points == 128.4)
        #expect(game.away?.points == 121.7)
    }
}

@Suite("Boxscore")
struct ESPNBoxscoreTests {
    /// Slots out of lineup order on purpose — ESPN returns them in roster
    /// order, not the order a lineup is read in.
    private static let payload = """
    {
      "id": 1234567,
      "schedule": [{
        "id": 1, "matchupPeriodId": 1, "winner": "UNDECIDED",
        "home": {
          "teamId": 10, "totalPoints": 0.0, "totalPointsLive": 21.4,
          "rosterForCurrentScoringPeriod": {"entries": [
            {"lineupSlotId": 20, "playerPoolEntry": {"appliedStatTotal": 0.0,
              "player": {"id": 5, "fullName": "Benched Barry", "defaultPositionId": 1}}},
            {"lineupSlotId": 23, "playerPoolEntry": {"appliedStatTotal": 7.8,
              "player": {"id": 3, "fullName": "Flex Fred", "defaultPositionId": 2}}},
            {"lineupSlotId": 0, "playerPoolEntry": {"appliedStatTotal": 13.6,
              "player": {"id": 1, "fullName": "Quarter Quinn", "defaultPositionId": 1}}},
            {"lineupSlotId": 21, "playerPoolEntry": {"appliedStatTotal": 0.0,
              "player": {"id": 6, "fullName": "Injured Ivy", "defaultPositionId": 3}}},
            {"lineupSlotId": 4, "playerPoolEntry": {"appliedStatTotal": 0.0,
              "player": {"id": 2, "fullName": "Wide Wendy", "defaultPositionId": 3}}}
          ]}
        },
        "away": {"teamId": 7, "totalPoints": 0.0, "totalPointsLive": 6.0}
      }]
    }
    """

    @Test("Starters come back in lineup order, with the bench after them")
    func rosterOrder() async throws {
        let matchups = try await clientOverPayload(Self.payload).matchups(week: 1)
        let home = try #require(matchups.first).home

        #expect(home.roster.map(\.name) == [
            "Quarter Quinn", "Wide Wendy", "Flex Fred", "Benched Barry", "Injured Ivy",
        ])
        #expect(home.starters.map(\.slot) == ["QB", "WR", "FLEX"])
        #expect(home.bench.map(\.slot) == ["Bench", "IR"])
    }

    @Test("A player keeps their own position, not the slot they are filling")
    func positionVersusSlot() async throws {
        let matchups = try await clientOverPayload(Self.payload).matchups(week: 1)
        let home = try #require(matchups.first).home
        let flex = try #require(home.roster.first { $0.name == "Flex Fred" })
        // A running back in the flex is an RB in FLEX, not a FLEX.
        #expect(flex.position == "RB")
        #expect(flex.slot == "FLEX")
        #expect(flex.points == 7.8)
    }

    @Test("A side with no boxscore in the payload has an empty roster, not a crash")
    func missingRoster() async throws {
        let matchups = try await clientOverPayload(Self.payload).matchups(week: 1)
        let matchup = try #require(matchups.first)
        let away = try #require(matchup.away)
        #expect(away.roster.isEmpty)
        #expect(away.points == 6.0)
    }
}

@Suite("ESPN request building")
struct ESPNRequestTests {
    @Test("URL carries the season, league id and one query item per view")
    func urlShape() throws {
        let config = ESPNConfiguration(leagueID: "1234567", season: 2025)
        let url = try #require(config.requestURL(views: ["mTeam", "mSettings"]))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.host == "lm-api-reads.fantasy.espn.com")
        #expect(components.path == "/apis/v3/games/ffl/seasons/2025/segments/0/leagues/1234567")
        // Repeated `view` params, not a comma-joined list — ESPN returns a
        // partial payload for the latter.
        #expect(components.queryItems?.filter { $0.name == "view" }.count == 2)
    }

    @Test("SWID is brace-wrapped whether or not the caller wrapped it")
    func swidNormalisation() {
        let bare = ESPNCredentials(espnS2: "s2", swid: "ABC-123")
        let wrapped = ESPNCredentials(espnS2: "s2", swid: "{ABC-123}")
        #expect(bare.swid == "{ABC-123}")
        #expect(bare.cookieHeader == wrapped.cookieHeader)
        #expect(bare.cookieHeader == "espn_s2=s2; SWID={ABC-123}")
    }

    /// Everything a human might realistically paste out of developer tools.
    @Test(arguments: [
        "ABC-123",
        "{ABC-123}",
        "  {ABC-123}  ",
        "%7BABC-123%7D",
        "%7babc-123%7d".uppercased(),
    ])
    func swidAcceptsPastedForms(raw: String) {
        let credentials = ESPNCredentials(espnS2: "s2", swid: raw)
        #expect(credentials.swid == "{ABC-123}")
    }

    @Test("espn_s2 keeps its percent-encoding but loses stray whitespace")
    func espnS2Handling() {
        // The cookie value really does contain % escapes; they are part of it
        // and must be sent through untouched.
        let credentials = ESPNCredentials(espnS2: "  AEB%2Fxyz%3D\n", swid: "{A}")
        #expect(credentials.espnS2 == "AEB%2Fxyz%3D")
        #expect(credentials.cookieHeader == "espn_s2=AEB%2Fxyz%3D; SWID={A}")
    }

    @Test("Credentials are sent as a Cookie header")
    func sendsCookieHeader() async throws {
        let captured = Captured()
        let client = try makeClient(
            credentials: ESPNCredentials(espnS2: "secret", swid: "{ABC}"),
            onRequest: { captured.store($0) }
        )
        _ = try await client.league()
        #expect(captured.value?.value(forHTTPHeaderField: "Cookie") == "espn_s2=secret; SWID={ABC}")
    }

    @Test("Public leagues send no Cookie header")
    func omitsCookieWhenPublic() async throws {
        let captured = Captured()
        let client = try makeClient(onRequest: { captured.store($0) })
        _ = try await client.league()
        #expect(captured.value?.value(forHTTPHeaderField: "Cookie") == nil)
    }
}

/// Minimal thread-safe box for capturing a request from the stub transport.
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

@Suite("ESPN mapping")
struct ESPNMappingTests {
    @Test("League settings map across")
    func league() async throws {
        let league = try await makeClient().league()
        #expect(league.id == "1234567")
        #expect(league.name == "Commissioners Cartel")
        #expect(league.season == 2025)
        #expect(league.currentWeek == 11)
        #expect(league.regularSeasonWeeks == 14)
        #expect(league.teamCount == 3)
        #expect(!league.isPlayoffs)
    }

    @Test("Members map to managers, including the commissioner flag")
    func managers() async throws {
        let managers = try await makeClient().managers()
        #expect(managers.count == 3)

        let commissioner = try #require(managers.first { $0.isCommissioner })
        #expect(commissioner.fullName == "Michael Smith")

        // ESPN omits firstName/lastName for some members.
        let anonymous = try #require(managers.first { $0.displayName == "dtaylor" })
        #expect(anonymous.fullName == "dtaylor")
        #expect(!anonymous.isCommissioner)
    }

    @Test("Modern `name` and legacy `location`+`nickname` both produce a team name")
    func teamNaming() async throws {
        let teams = try await makeClient().teams()
        #expect(teams.count == 3)
        #expect(teams[0].name == "Bear Necessities")
        #expect(teams[1].name == "Trap Game")
        // No name of any kind — fall back rather than showing blank.
        #expect(teams[2].name == "Team 3")
    }

    @Test("Records and seeds map across")
    func teamRecords() async throws {
        let teams = try await makeClient().teams()
        #expect(teams[0].record.summary == "8-2")
        #expect(teams[1].record.summary == "7-2-1")
        #expect(teams[0].playoffSeed == 1)
        #expect(teams[0].logoURL?.absoluteString == "https://example.com/logo1.png")
        // Falls back to primaryOwner when `owners` is absent.
        #expect(teams[1].ownerIDs == ["{BBBBBBBB-1111-2222-3333-444444444444}"])
        // No record at all in the payload.
        #expect(teams[2].record == .empty)
    }

    @Test("Only the requested week's matchups come back")
    func matchupsFilterByWeek() async throws {
        let client = try makeClient()
        let week10 = try await client.matchups(week: 10)
        #expect(week10.count == 1)
        #expect(week10[0].isComplete)
        #expect(week10[0].winningTeamID == 1)
        // Projections are dropped once a game is final.
        #expect(week10[0].home.projectedPoints == nil)

        let week11 = try await client.matchups(week: 11)
        #expect(week11.count == 2)
        let noneComplete = week11.allSatisfy { !$0.isComplete }
        #expect(noneComplete)
        #expect(week11[0].home.projectedPoints == 124.7)
        #expect(week11[0].winningTeamID == nil, "UNDECIDED games have no winner")
    }

    @Test("A schedule entry with no away side is a bye")
    func byeMatchup() async throws {
        let week11 = try await makeClient().matchups(week: 11)
        let bye = try #require(week11.first { $0.isBye })
        #expect(bye.away == nil)
        #expect(bye.home.teamID == 2)
    }

    @Test("An unplayed week is empty, not an error")
    func unknownWeekIsEmpty() async throws {
        let matchups = try await makeClient().matchups(week: 14)
        #expect(matchups.isEmpty)
    }
}

@Suite("ESPN caching and errors")
struct ESPNCachingTests {
    /// Thread-safe request counter.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    @Test("Four screens' worth of calls hit the network once")
    func cachesAcrossCalls() async throws {
        let counter = Counter()
        let client = try makeClient(onRequest: { _ in counter.increment() })

        _ = try await client.league()
        _ = try await client.teams()
        _ = try await client.managers()
        _ = try await client.matchups(week: 11)

        #expect(counter.value == 1)
    }

    @Test("Concurrent callers share one in-flight request")
    func coalescesConcurrentCalls() async throws {
        let counter = Counter()
        let client = try makeClient(onRequest: { _ in counter.increment() })

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { _ = try? await client.teams() }
            }
        }

        #expect(counter.value == 1)
    }

    @Test("The cache expires after its TTL")
    func cacheExpires() async throws {
        let counter = Counter()
        let clock = MutableClock()
        let client = try makeClient(
            cacheTTL: .seconds(60),
            now: { clock.now },
            onRequest: { _ in counter.increment() }
        )

        _ = try await client.league()
        clock.advance(by: 30)
        _ = try await client.league()
        #expect(counter.value == 1, "still fresh")

        clock.advance(by: 31)
        _ = try await client.league()
        #expect(counter.value == 2, "TTL elapsed")
    }

    @Test("invalidateCache forces the next call back to the network")
    func manualInvalidation() async throws {
        let counter = Counter()
        let client = try makeClient(onRequest: { _ in counter.increment() })

        _ = try await client.league()
        await client.invalidateCache()
        _ = try await client.league()

        #expect(counter.value == 2)
    }

    @Test("401 and 403 surface as notAuthorized, not a raw status code")
    func unauthorized() async throws {
        for status in [401, 403] {
            let client = try makeClient(statusCode: status)
            await #expect(throws: CartelError.self) { _ = try await client.league() }
        }
    }

    @Test("Other failures keep their status code")
    func serverError() async throws {
        let client = try makeClient(statusCode: 500)
        do {
            _ = try await client.league()
            Issue.record("Expected a server error")
        } catch let error as CartelError {
            guard case let .server(statusCode, _) = error else {
                Issue.record("Expected .server, got \(error)")
                return
            }
            #expect(statusCode == 500)
        }
    }

    @Test("An empty league id fails fast without a request")
    func missingLeagueID() async {
        let counter = Counter()
        let client = ESPNClient(
            configuration: ESPNConfiguration(leagueID: "", season: 2025),
            transport: StubTransport { request in
                counter.increment()
                return (Data(), HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!)
            }
        )
        await #expect(throws: CartelError.self) { _ = try await client.league() }
        #expect(counter.value == 0)
    }
}

private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var offset: TimeInterval = 0

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return Date(timeIntervalSince1970: offset)
    }

    func advance(by seconds: TimeInterval) {
        lock.lock(); offset += seconds; lock.unlock()
    }
}

@Suite("Proxy configuration")
struct ESPNProxyTests {
    @Test("viaProxy keeps ESPN's path shape under the function URL")
    func proxyURL() throws {
        let config = ESPNConfiguration.viaProxy(
            leagueID: "1234567",
            season: 2025,
            supabaseURL: URL(string: "https://abcdefgh.supabase.co")!,
            accessToken: "jwt-abc"
        )
        let url = try #require(config.requestURL(views: ["mTeam"]))

        #expect(url.host() == "abcdefgh.supabase.co")
        #expect(url.path() == "/functions/v1/espn-proxy/apis/v3/games/ffl/seasons/2025/segments/0/leagues/1234567")
        // Cookies stay server-side; the app only sends its Supabase token.
        #expect(config.credentials == nil)
        #expect(config.additionalHeaders["Authorization"] == "Bearer jwt-abc")
    }

    @Test("Additional headers are sent on the request")
    func sendsAdditionalHeaders() async throws {
        let captured = Captured()
        let transport = StubTransport { request in
            captured.store(request)
            return (Data("{\"id\":1}".utf8), HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!)
        }
        let client = ESPNClient(
            configuration: ESPNConfiguration(
                leagueID: "1", season: 2025, additionalHeaders: ["Authorization": "Bearer xyz"]
            ),
            transport: transport
        )
        _ = try await client.league()
        #expect(captured.value?.value(forHTTPHeaderField: "Authorization") == "Bearer xyz")
    }
}

/// A brand-new league before week 1, captured from a real ESPN response.
///
/// Preseason differs from mid-season in ways that are easy to get wrong and
/// invisible until September: seeds are `0` rather than absent, records are all
/// zeroes, `isLeagueManager` is missing from every member, and no side carries
/// a projection.
@Suite("ESPN preseason payload")
struct ESPNPreseasonTests {
    private func client() throws -> ESPNClient {
        try makeClient(fixture: "preseason")
    }

    @Test("Seed 0 is treated as no seed, not as first place")
    func zeroSeedIsNotASeed() async throws {
        let teams = try await client().teams()
        // Rendering 0 as a real seed shows "#0" and makes the standings sort
        // meaningless, since every team ties at zero.
        #expect(teams.allSatisfy { $0.playoffSeed == nil })
    }

    @Test("A league that hasn't played has empty records, not missing teams")
    func emptyRecords() async throws {
        let teams = try await client().teams()
        #expect(teams.count == 2)
        #expect(teams.allSatisfy { $0.record.gamesPlayed == 0 })
        #expect(teams.allSatisfy { $0.record.summary == "0-0" })
        #expect(teams[0].name == "Team Alpha")
    }

    @Test("Members still map when ESPN omits isLeagueManager entirely")
    func membersWithoutCommissionerFlag() async throws {
        let managers = try await client().managers()
        #expect(managers.count == 2)
        #expect(managers.allSatisfy { !$0.isCommissioner })
        #expect(managers[0].fullName == "Alex One")
    }

    @Test("Week 1 is scheduled but unplayed, with no projections")
    func unplayedSchedule() async throws {
        let matchups = try await client().matchups(week: 1)
        #expect(matchups.count == 1)

        let game = try #require(matchups.first)
        #expect(!game.isComplete)
        #expect(game.winningTeamID == nil)
        #expect(game.home.points == 0)
        // Preseason payloads carry no totalProjectedPointsLive at all.
        #expect(game.home.projectedPoints == nil)
        #expect(game.away?.projectedPoints == nil)
    }

    @Test("League settings survive a preseason payload")
    func leagueSettings() async throws {
        let league = try await client().league()
        #expect(league.currentWeek == 1)
        #expect(league.regularSeasonWeeks == 14)
        #expect(league.teamCount == 2)
        #expect(!league.isPlayoffs)
    }
}

@Suite("Divisions and logos")
struct ESPNDivisionAndLogoTests {
    private static let proxyBase = URL(string: "https://abc.supabase.co/functions/v1/espn-proxy")!

    private func client(imageProxy: URL? = nil) throws -> ESPNClient {
        let data = try Fixture.data("preseason")
        return ESPNClient(
            configuration: ESPNConfiguration(
                leagueID: "1", season: 2026, imageProxyBase: imageProxy
            ),
            transport: StubTransport(data: data)
        )
    }

    @Test("Divisions map off the schedule settings")
    func divisions() async throws {
        let league = try await client().league()
        #expect(league.hasDivisions)
        #expect(league.divisions.map(\.name) == ["Division A", "Division B"])
        #expect(league.divisions.map(\.id) == [0, 1])
    }

    @Test("Teams carry their division id")
    func teamDivisions() async throws {
        let teams = try await client().teams()
        #expect(teams[0].divisionID == 0)
        #expect(teams[1].divisionID == 1)
    }

    @Test("A league without divisions reports none")
    func noDivisions() async throws {
        // The mid-season fixture has no divisions block at all.
        let league = try await makeClient().league()
        #expect(league.divisions.isEmpty)
        #expect(!league.hasDivisions)
    }

    /// Public CDN logos need no help and must not be rewritten — routing them
    /// through the proxy would 400, since the function only allows ESPN's own
    /// image path.
    @Test("Public CDN logos are left alone")
    func publicLogoUntouched() async throws {
        let teams = try await client(imageProxy: Self.proxyBase).teams()
        #expect(teams[0].logoURL?.absoluteString == "https://example.com/a.png")
    }

    @Test("Uploaded logos are rewritten through the proxy")
    func uploadedLogoIsProxied() throws {
        let dto = ESPNLeagueResponse.TeamDTO(
            id: 1, abbrev: "A", name: "A", location: nil, nickname: nil,
            logo: "https://mystique-api.fantasy.espn.com/apis/v1/domains/lm/images/abc123",
            owners: nil, primaryOwner: nil, playoffSeed: nil, divisionId: nil, record: nil
        )
        let url = ESPNMapper.logoURL(for: dto, imageProxyBase: Self.proxyBase)
        #expect(url?.absoluteString ==
                "https://abc.supabase.co/functions/v1/espn-proxy/apis/v1/domains/lm/images/abc123")
    }

    /// Without a proxy the app has no way to authenticate the request, so
    /// reporting no logo beats handing the UI a URL that always 401s.
    @Test("Uploaded logos report nil when there is no proxy")
    func uploadedLogoWithoutProxy() throws {
        let dto = ESPNLeagueResponse.TeamDTO(
            id: 1, abbrev: "A", name: "A", location: nil, nickname: nil,
            logo: "https://mystique-api.fantasy.espn.com/apis/v1/domains/lm/images/abc123",
            owners: nil, primaryOwner: nil, playoffSeed: nil, divisionId: nil, record: nil
        )
        #expect(ESPNMapper.logoURL(for: dto, imageProxyBase: nil) == nil)
    }

    @Test("A team with no logo stays nil")
    func missingLogo() throws {
        let dto = ESPNLeagueResponse.TeamDTO(
            id: 1, abbrev: "A", name: "A", location: nil, nickname: nil,
            logo: nil, owners: nil, primaryOwner: nil, playoffSeed: nil,
            divisionId: nil, record: nil
        )
        #expect(ESPNMapper.logoURL(for: dto, imageProxyBase: Self.proxyBase) == nil)
    }
}

@Suite("Logo source selection")
struct ESPNLogoSourceTests {
    private static let proxyBase = URL(string: "https://abc.supabase.co/functions/v1/espn-proxy")!

    private func team(logo: String?) -> ESPNLeagueResponse.TeamDTO {
        ESPNLeagueResponse.TeamDTO(
            id: 1, abbrev: "A", name: "A", location: nil, nickname: nil,
            logo: logo, owners: nil, primaryOwner: nil,
            playoffSeed: nil, divisionId: nil, record: nil
        )
    }

    /// ESPN's stock art is SVG and UIImage cannot decode it. Reporting nil lets
    /// the UI show the league's own avatar immediately, rather than firing a
    /// request per team on every launch that can only fail.
    @Test(arguments: [
        "https://g.espncdn.com/lm-static/ffl/images/default_logos/20.svg",
        "https://g.espncdn.com/lm-static/logo-packs/ffl/BoneHeads/BoneHeads-05.svg",
        "https://example.com/UPPERCASE.SVG",
    ])
    func svgLogosAreTreatedAsAbsent(url: String) {
        #expect(ESPNMapper.logoURL(for: team(logo: url), imageProxyBase: Self.proxyBase) == nil)
    }

    @Test("An uploaded raster logo still routes through the proxy")
    func uploadedLogoSurvives() {
        let url = ESPNMapper.logoURL(
            for: team(logo: "https://mystique-api.fantasy.espn.com/apis/v1/domains/lm/images/abc"),
            imageProxyBase: Self.proxyBase
        )
        #expect(url?.absoluteString.hasSuffix("/apis/v1/domains/lm/images/abc") == true)
    }

    @Test("A raster logo on some other host is left alone")
    func otherRasterLogo() {
        let url = ESPNMapper.logoURL(
            for: team(logo: "https://example.com/team.png"), imageProxyBase: Self.proxyBase
        )
        #expect(url?.absoluteString == "https://example.com/team.png")
    }

    /// The behaviour the league asked for: upload an image and it replaces the
    /// placeholder next time the app reads from ESPN. Nothing is cached across
    /// launches, so the switch needs no other action.
    @Test("Switching from stock art to an upload changes the resolved URL")
    func uploadReplacesPlaceholder() {
        let before = ESPNMapper.logoURL(
            for: team(logo: "https://g.espncdn.com/lm-static/ffl/images/default_logos/20.svg"),
            imageProxyBase: Self.proxyBase
        )
        let after = ESPNMapper.logoURL(
            for: team(logo: "https://mystique-api.fantasy.espn.com/apis/v1/domains/lm/images/new"),
            imageProxyBase: Self.proxyBase
        )
        #expect(before == nil, "placeholder while on stock art")
        #expect(after != nil, "real logo once uploaded")
    }
}

@Suite("Refreshing")
struct ESPNRefreshTests {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    /// Pull-to-refresh must actually go to the network. Before `refresh()`
    /// existed, pulling within the cache TTL replayed the old payload, so a
    /// freshly uploaded logo or renamed team appeared not to have changed.
    @Test("refresh() forces the next read back to the network")
    func refreshBypassesCache() async throws {
        let counter = Counter()
        let client = try makeClient(onRequest: { _ in counter.increment() })

        _ = try await client.teams()
        _ = try await client.teams()
        #expect(counter.value == 1, "second read served from cache")

        await client.refresh()
        _ = try await client.teams()
        #expect(counter.value == 2, "refresh went back to the network")
    }

    @Test("A source with nothing cached treats refresh as a no-op")
    func defaultRefreshIsHarmless() async throws {
        let mock = MockLeagueDataSource(latency: .zero)
        await mock.refresh()
        #expect(try await mock.teams().count == MockData.teams.count)
    }
}
