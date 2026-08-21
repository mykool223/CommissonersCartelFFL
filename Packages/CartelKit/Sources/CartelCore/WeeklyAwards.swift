import Foundation

/// A superlative for one week of play.
public struct WeeklyAward: Identifiable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Hashable, Sendable {
        case highestScore
        case lowestScore
        case biggestBlowout
        case closestGame
        case shootout
        /// Lost while outscoring most of the league.
        case unluckiest
        /// Won with a score that would have lost most other matchups.
        case luckiest
        /// Biggest jump from the previous week. ESPN's payload carries no
        /// in-game trajectory, so this stands in for "comeback": it measures a
        /// team turning its season around, not a fourth-quarter rally.
        case mostImproved
    }

    public let kind: Kind
    /// The team the award is about.
    public let teamID: Int
    /// The other side, for awards that describe a matchup rather than a team.
    public let opponentID: Int?
    /// The number behind the award: points, margin, or improvement.
    public let value: Double
    /// Secondary number, e.g. the losing score in a blowout.
    public let secondaryValue: Double?

    public var id: Kind { kind }

    public init(
        kind: Kind,
        teamID: Int,
        opponentID: Int? = nil,
        value: Double,
        secondaryValue: Double? = nil
    ) {
        self.kind = kind
        self.teamID = teamID
        self.opponentID = opponentID
        self.value = value
        self.secondaryValue = secondaryValue
    }
}

/// Derives the week's superlatives from matchups already in hand.
///
/// Pure computation over data the app has already fetched — one ESPN payload
/// carries the whole season's schedule, so even the week-over-week comparison
/// costs nothing extra.
public enum WeeklyAwards {
    /// One side of a matchup, paired with its opponent.
    private struct Performance {
        let teamID: Int
        let points: Double
        let opponentID: Int?
        let opponentPoints: Double?

        var won: Bool {
            guard let opponentPoints else { return false }
            return points > opponentPoints
        }

        var lost: Bool {
            guard let opponentPoints else { return false }
            return points < opponentPoints
        }
    }

    /// - Parameters:
    ///   - matchups: the week being summarised.
    ///   - previousWeek: the week before, for `mostImproved`. Pass an empty
    ///     array in week 1.
    /// - Returns: the awards that can be determined, newest-first order not
    ///   guaranteed. Empty when no game in the week has been played.
    public static func compute(
        matchups: [Matchup],
        previousWeek: [Matchup] = []
    ) -> [WeeklyAward] {
        // Awards for a week nobody has played would just be a list of zeroes.
        let played = matchups.filter(\.hasStarted)
        guard !played.isEmpty else { return [] }

        let performances = played.flatMap { matchup -> [Performance] in
            guard let away = matchup.away else {
                // A bye still counts for scoring awards; it has no opponent.
                return [Performance(
                    teamID: matchup.home.teamID, points: matchup.home.points,
                    opponentID: nil, opponentPoints: nil
                )]
            }
            return [
                Performance(
                    teamID: matchup.home.teamID, points: matchup.home.points,
                    opponentID: away.teamID, opponentPoints: away.points
                ),
                Performance(
                    teamID: away.teamID, points: away.points,
                    opponentID: matchup.home.teamID, opponentPoints: matchup.home.points
                ),
            ]
        }

        var awards: [WeeklyAward] = []

        if let best = performances.max(by: { $0.points < $1.points }) {
            awards.append(WeeklyAward(
                kind: .highestScore, teamID: best.teamID,
                opponentID: best.opponentID, value: best.points
            ))
        }

        if let worst = performances.min(by: { $0.points < $1.points }) {
            awards.append(WeeklyAward(
                kind: .lowestScore, teamID: worst.teamID,
                opponentID: worst.opponentID, value: worst.points
            ))
        }

        // Head-to-head awards ignore byes, which have no margin.
        let contested = played.filter { !$0.isBye }

        if let blowout = contested.max(by: { $0.margin < $1.margin }), blowout.margin > 0 {
            let winner = blowout.home.points > (blowout.away?.points ?? 0) ? blowout.home : blowout.away!
            let loser = blowout.home.teamID == winner.teamID ? blowout.away! : blowout.home
            awards.append(WeeklyAward(
                kind: .biggestBlowout, teamID: winner.teamID,
                opponentID: loser.teamID, value: blowout.margin,
                secondaryValue: winner.points
            ))
        }

        if let closest = contested.min(by: { $0.margin < $1.margin }) {
            let leader = closest.home.points >= (closest.away?.points ?? 0) ? closest.home : closest.away!
            let other = closest.home.teamID == leader.teamID ? closest.away! : closest.home
            awards.append(WeeklyAward(
                kind: .closestGame, teamID: leader.teamID,
                opponentID: other.teamID, value: closest.margin,
                secondaryValue: leader.points
            ))
        }

        if let shootout = contested.max(by: { $0.combinedPoints < $1.combinedPoints }) {
            awards.append(WeeklyAward(
                kind: .shootout, teamID: shootout.home.teamID,
                opponentID: shootout.away?.teamID, value: shootout.combinedPoints
            ))
        }

        // The highest-scoring loser: a good week wasted.
        if let unlucky = performances.filter(\.lost).max(by: { $0.points < $1.points }) {
            awards.append(WeeklyAward(
                kind: .unluckiest, teamID: unlucky.teamID,
                opponentID: unlucky.opponentID, value: unlucky.points,
                secondaryValue: unlucky.opponentPoints
            ))
        }

        // The lowest-scoring winner: got away with one.
        if let lucky = performances.filter(\.won).min(by: { $0.points < $1.points }) {
            awards.append(WeeklyAward(
                kind: .luckiest, teamID: lucky.teamID,
                opponentID: lucky.opponentID, value: lucky.points,
                secondaryValue: lucky.opponentPoints
            ))
        }

        if let improved = mostImproved(performances: performances, previousWeek: previousWeek) {
            awards.append(improved)
        }

        return awards
    }

    private static func mostImproved(
        performances: [Performance],
        previousWeek: [Matchup]
    ) -> WeeklyAward? {
        let previousPlayed = previousWeek.filter(\.hasStarted)
        guard !previousPlayed.isEmpty else { return nil }

        var lastWeek: [Int: Double] = [:]
        for matchup in previousPlayed {
            lastWeek[matchup.home.teamID] = matchup.home.points
            if let away = matchup.away {
                lastWeek[away.teamID] = away.points
            }
        }

        let gains = performances.compactMap { performance -> (Int, Double)? in
            guard let previous = lastWeek[performance.teamID] else { return nil }
            return (performance.teamID, performance.points - previous)
        }

        // Only celebrate an actual improvement.
        guard let best = gains.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
        return WeeklyAward(kind: .mostImproved, teamID: best.0, value: best.1)
    }
}
