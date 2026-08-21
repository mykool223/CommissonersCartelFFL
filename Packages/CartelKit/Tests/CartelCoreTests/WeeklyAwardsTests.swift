import Foundation
import Testing
@testable import CartelCore

@Suite("Weekly awards")
struct WeeklyAwardsTests {
    /// Builds a finished matchup.
    private func game(_ home: Int, _ homePoints: Double,
                      _ away: Int, _ awayPoints: Double,
                      week: Int = 2) -> Matchup {
        Matchup(
            id: home * 100 + away, week: week,
            home: MatchupSide(teamID: home, points: homePoints),
            away: MatchupSide(teamID: away, points: awayPoints),
            isComplete: true
        )
    }

    /// A representative week: a blowout, a nail-biter and a shootout.
    private var week: [Matchup] {
        [
            game(1, 150.0, 2, 90.0),    // blowout, and the week's high
            game(3, 110.5, 4, 110.0),   // closest game
            game(5, 140.0, 6, 138.0),   // shootout by combined points
            game(7, 100.0, 8, 88.0),
        ]
    }

    private func award(_ kind: WeeklyAward.Kind, in awards: [WeeklyAward]) throws -> WeeklyAward {
        try #require(awards.first { $0.kind == kind }, "no \(kind) award")
    }

    @Test("Highest and lowest scores")
    func extremes() throws {
        let awards = WeeklyAwards.compute(matchups: week)
        let high = try award(.highestScore, in: awards)
        #expect(high.teamID == 1)
        #expect(high.value == 150.0)

        let low = try award(.lowestScore, in: awards)
        #expect(low.teamID == 8)
        #expect(low.value == 88.0)
    }

    @Test("Blowout reports the winner and the margin")
    func blowout() throws {
        let result = try award(.biggestBlowout, in: WeeklyAwards.compute(matchups: week))
        #expect(result.teamID == 1)
        #expect(result.opponentID == 2)
        #expect(result.value == 60.0)
    }

    @Test("Closest game finds the smallest margin")
    func closest() throws {
        let result = try award(.closestGame, in: WeeklyAwards.compute(matchups: week))
        #expect(result.teamID == 3)
        #expect(result.opponentID == 4)
        #expect(abs(result.value - 0.5) < 0.001)
    }

    @Test("Shootout ranks on combined points, not margin")
    func shootout() throws {
        let result = try award(.shootout, in: WeeklyAwards.compute(matchups: week))
        // 140 + 138 = 278 beats the blowout's 240.
        #expect(abs(result.value - 278.0) < 0.001)
    }

    @Test("Unluckiest is the highest-scoring loser, not simply the loser")
    func unluckiest() throws {
        let result = try award(.unluckiest, in: WeeklyAwards.compute(matchups: week))
        // Team 6 lost with 138 — more than three winners scored.
        #expect(result.teamID == 6)
        #expect(result.value == 138.0)
    }

    @Test("Luckiest is the lowest-scoring winner")
    func luckiest() throws {
        let result = try award(.luckiest, in: WeeklyAwards.compute(matchups: week))
        #expect(result.teamID == 7)
        #expect(result.value == 100.0)
    }

    @Test("Most improved compares against the previous week")
    func mostImproved() throws {
        let previous = [
            game(1, 145.0, 2, 95.0, week: 1),
            game(3, 60.0, 4, 100.0, week: 1),   // team 3 jumps 110.5 - 60 = 50.5
            game(5, 130.0, 6, 120.0, week: 1),
            game(7, 99.0, 8, 80.0, week: 1),
        ]
        let result = try award(.mostImproved, in: WeeklyAwards.compute(matchups: week, previousWeek: previous))
        #expect(result.teamID == 3)
        #expect(abs(result.value - 50.5) < 0.001)
    }

    @Test("Week 1 has no most-improved award")
    func noPreviousWeek() {
        let awards = WeeklyAwards.compute(matchups: week, previousWeek: [])
        #expect(!awards.contains { $0.kind == .mostImproved })
    }

    /// Guards against celebrating a team that got worse simply because
    /// everyone else got worse faster.
    @Test("Nobody improving means no award")
    func everyoneRegressed() {
        let previous = week.map {
            game($0.home.teamID, $0.home.points + 20, $0.away!.teamID, $0.away!.points + 20, week: 1)
        }
        let awards = WeeklyAwards.compute(matchups: week, previousWeek: previous)
        #expect(!awards.contains { $0.kind == .mostImproved })
    }

    @Test("An unplayed week produces nothing rather than a list of zeroes")
    func unplayedWeek() {
        let scheduled = [
            Matchup(id: 1, week: 1,
                    home: MatchupSide(teamID: 1, points: 0),
                    away: MatchupSide(teamID: 2, points: 0),
                    isComplete: false),
        ]
        #expect(WeeklyAwards.compute(matchups: scheduled).isEmpty)
    }

    @Test("A bye counts for scoring awards but not head-to-head ones")
    func byeWeek() throws {
        let matchups = [
            game(1, 120.0, 2, 100.0),
            Matchup(id: 99, week: 2,
                    home: MatchupSide(teamID: 3, points: 200.0),
                    away: nil, isComplete: true),
        ]
        let awards = WeeklyAwards.compute(matchups: matchups)
        // The bye team posted the week's best score.
        #expect(try award(.highestScore, in: awards).teamID == 3)
        // ...but cannot have won a blowout, having played nobody.
        #expect(try award(.biggestBlowout, in: awards).teamID == 1)
    }

    @Test("A week of ties yields no lucky or unlucky team")
    func allTies() {
        let awards = WeeklyAwards.compute(matchups: [game(1, 100.0, 2, 100.0)])
        #expect(!awards.contains { $0.kind == .unluckiest })
        #expect(!awards.contains { $0.kind == .luckiest })
        // A tie is still the closest game of the week.
        #expect(awards.contains { $0.kind == .closestGame })
    }

    @Test("Partially played weeks use only what has been played")
    func partialWeek() throws {
        let matchups = [
            game(1, 130.0, 2, 90.0),
            Matchup(id: 5, week: 2,
                    home: MatchupSide(teamID: 5, points: 0),
                    away: MatchupSide(teamID: 6, points: 0),
                    isComplete: false),
        ]
        let awards = WeeklyAwards.compute(matchups: matchups)
        #expect(try award(.highestScore, in: awards).teamID == 1)
        // The unplayed 0-0 game must not win "lowest score".
        #expect(try award(.lowestScore, in: awards).teamID == 2)
    }
}
