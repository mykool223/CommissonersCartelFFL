import Foundation
import Testing
@testable import CartelCore

@Suite("TeamRecord")
struct TeamRecordTests {
    @Test("Ties count as half a win")
    func winPercentageCountsTiesAsHalf() {
        let record = TeamRecord(wins: 7, losses: 2, ties: 1, pointsFor: 0, pointsAgainst: 0)
        #expect(record.gamesPlayed == 10)
        #expect(abs(record.winPercentage - 0.75) < 0.0001)
    }

    @Test("A team that has not played yet is not a divide-by-zero")
    func winPercentageWithNoGames() {
        #expect(TeamRecord.empty.winPercentage == 0)
    }

    @Test("Summary omits ties when there are none")
    func summaryFormatting() {
        let noTies = TeamRecord(wins: 7, losses: 5, ties: 0, pointsFor: 0, pointsAgainst: 0)
        let withTies = TeamRecord(wins: 7, losses: 5, ties: 1, pointsFor: 0, pointsAgainst: 0)
        #expect(noTies.summary == "7-5")
        #expect(withTies.summary == "7-5-1")
    }
}

@Suite("Matchup")
struct MatchupTests {
    private func matchup(
        home: Double, away: Double?, isComplete: Bool
    ) -> Matchup {
        Matchup(
            id: 1,
            week: 10,
            home: MatchupSide(teamID: 1, points: home),
            away: away.map { MatchupSide(teamID: 2, points: $0) },
            isComplete: isComplete
        )
    }

    @Test("Winner is only reported once the game is final")
    func winnerRequiresCompletion() {
        #expect(matchup(home: 120, away: 100, isComplete: true).winningTeamID == 1)
        #expect(matchup(home: 100, away: 120, isComplete: true).winningTeamID == 2)
        #expect(matchup(home: 120, away: 100, isComplete: false).winningTeamID == nil)
    }

    @Test("A tie has no winner")
    func tieHasNoWinner() {
        #expect(matchup(home: 110, away: 110, isComplete: true).winningTeamID == nil)
    }

    @Test("A bye week has one side and no winner")
    func byeWeek() {
        let bye = matchup(home: 110, away: nil, isComplete: true)
        #expect(bye.isBye)
        #expect(bye.winningTeamID == nil)
        #expect(bye.margin == 0)
        #expect(bye.combinedPoints == 110)
    }
}

@Suite("Poll")
struct PollTests {
    private let base = Poll(
        id: MockData.uuid(1),
        question: "Who wins?",
        options: [
            PollOption(id: MockData.uuid(2), label: "A", voteCount: 3),
            PollOption(id: MockData.uuid(3), label: "B", voteCount: 1),
        ],
        season: 2025,
        createdByName: "Commish",
        createdAt: Date(timeIntervalSince1970: 0)
    )

    @Test("Shares sum to one when votes exist")
    func shares() {
        #expect(abs(base.share(of: base.options[0]) - 0.75) < 0.0001)
        #expect(abs(base.share(of: base.options[1]) - 0.25) < 0.0001)
    }

    @Test("An unvoted poll reports zero share rather than crashing")
    func sharesWithNoVotes() {
        let empty = Poll(
            id: MockData.uuid(4),
            question: "?",
            options: [PollOption(id: MockData.uuid(5), label: "A")],
            season: 2025,
            createdByName: "Commish",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        #expect(empty.totalVotes == 0)
        #expect(empty.share(of: empty.options[0]) == 0)
        #expect(empty.leadingOptions.isEmpty)
    }

    @Test("First vote increments the chosen option only")
    func firstVote() {
        let voted = base.applyingVote(optionID: base.options[1].id)
        #expect(voted.myVoteOptionID == base.options[1].id)
        #expect(voted.options[0].voteCount == 3)
        #expect(voted.options[1].voteCount == 2)
        #expect(voted.totalVotes == base.totalVotes + 1)
    }

    @Test("Changing a vote moves it instead of adding one")
    func changingVoteKeepsTotalStable() {
        let first = base.applyingVote(optionID: base.options[0].id)
        let changed = first.applyingVote(optionID: base.options[1].id)
        #expect(changed.totalVotes == first.totalVotes)
        #expect(changed.options[0].voteCount == 3)
        #expect(changed.options[1].voteCount == 2)
    }

    @Test("Re-voting for the same option is a no-op")
    func repeatVoteIsIdempotent() {
        let once = base.applyingVote(optionID: base.options[0].id)
        let twice = once.applyingVote(optionID: base.options[0].id)
        #expect(twice.options[0].voteCount == once.options[0].voteCount)
        #expect(twice.totalVotes == once.totalVotes)
    }

    @Test("Closing time is respected")
    func closesAt() {
        let closing = Date(timeIntervalSince1970: 1_000)
        let poll = Poll(
            id: MockData.uuid(6),
            question: "?",
            options: [],
            season: 2025,
            createdByName: "Commish",
            createdAt: Date(timeIntervalSince1970: 0),
            closesAt: closing
        )
        #expect(!poll.isClosed(asOf: Date(timeIntervalSince1970: 999)))
        #expect(poll.isClosed(asOf: closing))
        #expect(!base.isClosed(asOf: .distantFuture), "no closesAt means never closes")
    }
}

@Suite("NewsPost")
struct NewsPostTests {
    private func post(body: String) -> NewsPost {
        NewsPost(
            id: MockData.uuid(1),
            title: "T",
            body: body,
            authorName: "Commish",
            season: 2025,
            publishedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("Excerpt stops at the first paragraph")
    func excerptUsesFirstParagraph() {
        #expect(post(body: "First para.\n\nSecond para.").excerpt == "First para.")
    }

    @Test("Long paragraphs are truncated with an ellipsis")
    func excerptTruncates() {
        let long = String(repeating: "word ", count: 100)
        let excerpt = post(body: long).excerpt
        #expect(excerpt.hasSuffix("…"))
        #expect(excerpt.count <= 181)
    }
}

@Suite("Manager")
struct ManagerTests {
    @Test("Falls back to the display name when ESPN has no real name")
    func fullNameFallback() {
        let anonymous = Manager(id: "{X}", displayName: "punt_god")
        #expect(anonymous.fullName == "punt_god")
        #expect(anonymous.initials == "P")
    }

    @Test("Initials use first and last name")
    func initials() {
        let named = Manager(id: "{X}", displayName: "mykool223", firstName: "Michael", lastName: "Smith")
        #expect(named.fullName == "Michael Smith")
        #expect(named.initials == "MS")
    }
}

@Suite("MockContentRepository")
struct MockContentRepositoryTests {
    @Test("Voting persists across reads")
    func votePersists() async throws {
        let repo = MockContentRepository(latency: .zero)
        let poll = try #require(await repo.polls(season: MockData.season).first)
        let option = try #require(poll.options.last)

        try await repo.vote(pollID: poll.id, optionID: option.id)

        let updated = try #require(
            await repo.polls(season: MockData.season).first { $0.id == poll.id }
        )
        #expect(updated.myVoteOptionID == option.id)
        #expect(updated.totalVotes == poll.totalVotes + 1)
    }

    @Test("Voting for an option that isn't on the poll throws")
    func rejectsUnknownOption() async throws {
        let repo = MockContentRepository(latency: .zero)
        let poll = try #require(await repo.polls(season: MockData.season).first)
        await #expect(throws: CartelError.self) {
            try await repo.vote(pollID: poll.id, optionID: MockData.uuid(9_999))
        }
    }

    @Test("Injected failures propagate, for building error states")
    func injectedFailure() async {
        let repo = MockContentRepository(latency: .zero, failure: .notAuthorized)
        await #expect(throws: CartelError.self) {
            _ = try await repo.polls(season: MockData.season)
        }
    }
}

@Suite("MockData")
struct MockDataTests {
    @Test("Every team's owner exists in the manager list")
    func ownersResolve() {
        let managerIDs = Set(MockData.managers.map(\.id))
        for team in MockData.teams {
            for owner in team.ownerIDs {
                #expect(managerIDs.contains(owner), "Team \(team.name) has unknown owner \(owner)")
            }
        }
    }

    @Test("Each week schedules every team exactly once")
    func scheduleCoversAllTeams() {
        for week in 1...14 {
            let matchups = MockData.matchups(week: week)
            let teamIDs = matchups.flatMap { [$0.home.teamID] + ($0.away.map { [$0.teamID] } ?? []) }
            #expect(Set(teamIDs).count == MockData.teams.count, "week \(week)")
            #expect(teamIDs.count == MockData.teams.count, "week \(week) has a duplicate")
        }
    }

    @Test("Past weeks are final, the current week is not")
    func completionFlags() {
        let past = MockData.matchups(week: MockData.currentWeek - 1)
        let current = MockData.matchups(week: MockData.currentWeek)
        let pastAllComplete = past.allSatisfy { $0.isComplete }
        let currentNoneComplete = current.allSatisfy { !$0.isComplete }
        #expect(pastAllComplete)
        #expect(currentNoneComplete)
    }
}

@Suite("Season")
struct SeasonTests {
    private func date(_ iso: String) -> Date {
        try! Date.ISO8601FormatStyle().parse(iso)
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test("September through December belong to that calendar year")
    func inSeason() {
        #expect(Season.current(now: date("2026-09-10T12:00:00Z"), calendar: utc) == 2026)
        #expect(Season.current(now: date("2026-12-28T12:00:00Z"), calendar: utc) == 2026)
    }

    @Test("January and February still belong to the previous season")
    func januaryRollsBack() {
        // Playoffs run into the new calendar year; the season has not changed.
        #expect(Season.current(now: date("2027-01-15T12:00:00Z"), calendar: utc) == 2026)
        #expect(Season.current(now: date("2027-02-08T12:00:00Z"), calendar: utc) == 2026)
    }

    @Test("March is the rollover point")
    func marchRollsForward() {
        #expect(Season.current(now: date("2027-02-28T12:00:00Z"), calendar: utc) == 2026)
        #expect(Season.current(now: date("2027-03-01T12:00:00Z"), calendar: utc) == 2027)
    }

    @Test("The offseason still reports a season rather than nothing")
    func offseason() {
        #expect(Season.current(now: date("2026-06-01T12:00:00Z"), calendar: utc) == 2026)
    }
}

@Suite("Sample data stays current")
struct SampleDataFreshnessTests {
    /// The bug this guards: a hardcoded `MockData.season` matched nothing once
    /// the calendar rolled over, so every season-filtered screen went empty
    /// while the sample data sat there unused.
    @Test("MockData's season matches what the app will ask for")
    func seasonAgrees() {
        #expect(MockData.season == Season.current())
    }

    @Test("Sample content is actually reachable through the repository")
    func contentIsReachable() async throws {
        let repo = MockContentRepository(latency: .zero)
        let posts = try await repo.newsPosts(season: MockData.season, limit: 50)
        let polls = try await repo.polls(season: MockData.season)

        #expect(!posts.isEmpty, "News tab would render an empty state")
        #expect(!polls.isEmpty, "Polls tab would render an empty state")
    }

    @Test("Sample recaps are reachable for the current week")
    func recapsReachable() async throws {
        let repo = MockContentRepository(latency: .zero)
        let recaps = try await repo.recaps(season: MockData.season, week: MockData.currentWeek)
        #expect(!recaps.isEmpty)
    }
}

@Suite("Matchup status")
struct MatchupStatusTests {
    private func matchup(home: Double, away: Double, isComplete: Bool) -> Matchup {
        Matchup(
            id: 1, week: 1,
            home: MatchupSide(teamID: 1, points: home),
            away: MatchupSide(teamID: 2, points: away),
            isComplete: isComplete
        )
    }

    /// The preseason case. Every matchup is unplayed, and reporting them as
    /// "in progress" told the whole league that games were underway in August.
    @Test("An unplayed game is scheduled, not in progress")
    func unplayedIsScheduled() {
        let game = matchup(home: 0, away: 0, isComplete: false)
        #expect(game.status == .scheduled)
        #expect(!game.hasStarted)
    }

    @Test("Points on the board mean it is underway")
    func scoringMeansInProgress() {
        #expect(matchup(home: 12.4, away: 0, isComplete: false).status == .inProgress)
        #expect(matchup(home: 0, away: 9.1, isComplete: false).status == .inProgress)
    }

    @Test("A decided game is final regardless of score")
    func decidedIsFinal() {
        #expect(matchup(home: 110, away: 98, isComplete: true).status == .final)
        // A forfeited or zeroed-out game is still final.
        #expect(matchup(home: 0, away: 0, isComplete: true).status == .final)
    }

    @Test("A bye with no points is scheduled")
    func byeStatus() {
        let bye = Matchup(
            id: 1, week: 1,
            home: MatchupSide(teamID: 1, points: 0),
            away: nil, isComplete: false
        )
        #expect(bye.status == .scheduled)
    }
}

@Suite("Manager name cleanup")
struct ManagerNameTests {
    /// Real ESPN data: name fields routinely carry trailing spaces, which used
    /// to render as "Danny  Adams" with a double gap.
    @Test(arguments: [
        ("Danny ", "Adams"),
        ("Danny", " Adams"),
        (" Danny ", " Adams "),
        ("Danny", "Adams"),
    ])
    func trimsStrayWhitespace(name: (String, String)) {
        let manager = Manager(id: "{X}", displayName: "d", firstName: name.0, lastName: name.1)
        #expect(manager.fullName == "Danny Adams")
        #expect(manager.initials == "DA")
    }

    @Test("A whitespace-only name falls back to the display name")
    func blankNameFallsBack() {
        let manager = Manager(id: "{X}", displayName: "boogeyman ", firstName: "  ", lastName: "")
        #expect(manager.fullName == "boogeyman")
    }
}

@Suite("Flexible ISO-8601 parsing")
struct FlexibleISO8601Tests {
    /// The exact shape ESPN's scoreboard sends. The stock
    /// `Date.ISO8601FormatStyle` rejects it because the seconds field is
    /// missing, and the resulting fallback date rendered as a plausible-looking
    /// kickoff time on every game.
    @Test("Timestamps with no seconds parse")
    func missingSeconds() throws {
        let date = try #require(FlexibleISO8601.date(from: "2026-08-21T23:00Z"))
        #expect(date.timeIntervalSince1970 == 1_787_353_200)
    }

    @Test(arguments: [
        "2026-08-21T23:00:00Z",
        "2026-08-21T23:00Z",
        "2026-08-21T23:00:00.000Z",
        "2026-08-21T18:00:00-05:00",
        "2026-08-21T18:00-05:00",
    ])
    func acceptsEveryShapeSeenInTheWild(raw: String) throws {
        let date = try #require(FlexibleISO8601.date(from: raw), "failed on \(raw)")
        #expect(date.timeIntervalSince1970 == 1_787_353_200)
    }

    @Test(arguments: ["", "   ", "not a date", "2026-13-45T99:99Z", "1787353200"])
    func rejectsGarbage(raw: String) {
        #expect(FlexibleISO8601.date(from: raw) == nil)
    }
}

@Suite("NFL scoreboard ordering")
struct NFLScoreboardOrderingTests {
    private func game(_ id: String, _ state: NFLGame.State, _ start: Date?) -> NFLGame {
        NFLGame(
            id: id,
            home: NFLGame.Side(abbreviation: "AAA", name: "A"),
            away: NFLGame.Side(abbreviation: "BBB", name: "B"),
            state: state,
            startDate: start,
            statusDetail: ""
        )
    }

    @Test("Live first, then upcoming, then finished")
    func readingOrder() {
        let base = Date(timeIntervalSince1970: 1_787_353_200)
        let board = NFLScoreboard(
            seasonYear: 2026, week: 3, isPreseason: true,
            games: [
                game("final", .final, base),
                game("later", .scheduled, base.addingTimeInterval(7_200)),
                game("live", .inProgress, base),
                game("soon", .scheduled, base.addingTimeInterval(3_600)),
            ]
        )
        #expect(board.gamesInReadingOrder.map(\.id) == ["live", "soon", "later", "final"])
        #expect(board.hasLiveGames)
    }

    /// A game whose timestamp could not be parsed must not sort to 1970 and
    /// jump the queue ahead of everything else.
    @Test("Games with no timestamp sort last within their state")
    func undatedGamesSortLast() {
        let base = Date(timeIntervalSince1970: 1_787_353_200)
        let board = NFLScoreboard(
            seasonYear: 2026, week: 3, isPreseason: true,
            games: [
                game("undated", .scheduled, nil),
                game("dated", .scheduled, base),
            ]
        )
        #expect(board.gamesInReadingOrder.map(\.id) == ["dated", "undated"])
    }
}
