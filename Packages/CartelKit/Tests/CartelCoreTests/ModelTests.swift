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
