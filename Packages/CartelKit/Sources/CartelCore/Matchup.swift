import Foundation

/// One head-to-head game in a given week.
///
/// `away` is optional because leagues with an odd team count produce bye
/// matchups, which ESPN returns with only a home side.
public struct Matchup: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public let week: Int
    public let home: MatchupSide
    public let away: MatchupSide?
    public let isComplete: Bool

    public init(
        id: Int,
        week: Int,
        home: MatchupSide,
        away: MatchupSide?,
        isComplete: Bool
    ) {
        self.id = id
        self.week = week
        self.home = home
        self.away = away
        self.isComplete = isComplete
    }

    public var isBye: Bool { away == nil }

    /// True once either side has points on the board.
    ///
    /// `isComplete == false` alone does not mean a game is underway — before
    /// week 1 every matchup is scheduled but unplayed, and calling that
    /// "in progress" is just wrong.
    public var hasStarted: Bool {
        home.points > 0 || (away?.points ?? 0) > 0
    }

    public enum Status: Hashable, Sendable {
        case scheduled
        case inProgress
        case final
    }

    public var status: Status {
        if isComplete { return .final }
        return hasStarted ? .inProgress : .scheduled
    }

    /// Team id of the winner, or nil for a bye, a tie, or an unfinished game.
    public var winningTeamID: Int? {
        guard isComplete, let away else { return nil }
        if home.points > away.points { return home.teamID }
        if away.points > home.points { return away.teamID }
        return nil
    }

    /// Absolute scoring margin. Zero for byes and ties.
    public var margin: Double {
        guard let away else { return 0 }
        return abs(home.points - away.points)
    }

    /// Combined score, used to rank the week's shootouts.
    public var combinedPoints: Double {
        home.points + (away?.points ?? 0)
    }
}

public struct MatchupSide: Hashable, Sendable, Codable {
    public let teamID: Int
    public let points: Double
    /// ESPN's projected total. Nil once the games have been played.
    public let projectedPoints: Double?

    public init(teamID: Int, points: Double, projectedPoints: Double? = nil) {
        self.teamID = teamID
        self.points = points
        self.projectedPoints = projectedPoints
    }
}
