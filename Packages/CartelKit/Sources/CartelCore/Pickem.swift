import Foundation

/// One NFL fixture in the week's pick'em.
public struct PickemGame: Identifiable, Hashable, Sendable {
    public let season: Int
    public let week: Int
    /// ESPN's own event id.
    public let eventID: String
    public let homeAbbreviation: String
    public let homeName: String
    public let awayAbbreviation: String
    public let awayName: String
    public let kickoff: Date
    /// Nil until the game is decided. A tie leaves it nil and scores nobody.
    public let winnerAbbreviation: String?
    public let isFinal: Bool

    public var id: String { eventID }

    /// Picks are locked once the ball is in the air, per game rather than per
    /// week — a Sunday game should not be locked by a Thursday kickoff.
    public var isLocked: Bool { kickoff <= Date() }

    public init(
        season: Int, week: Int, eventID: String,
        homeAbbreviation: String, homeName: String,
        awayAbbreviation: String, awayName: String,
        kickoff: Date, winnerAbbreviation: String?, isFinal: Bool
    ) {
        self.season = season
        self.week = week
        self.eventID = eventID
        self.homeAbbreviation = homeAbbreviation
        self.homeName = homeName
        self.awayAbbreviation = awayAbbreviation
        self.awayName = awayName
        self.kickoff = kickoff
        self.winnerAbbreviation = winnerAbbreviation
        self.isFinal = isFinal
    }
}

/// Somebody's call on one game, and how sure they were.
public struct PickemPick: Identifiable, Hashable, Sendable {
    public let userID: UUID
    public let eventID: String
    public let chosenAbbreviation: String
    /// 1 up to the number of games that week, each value used once.
    public let confidence: Int

    public var id: String { "\(userID)-\(eventID)" }

    public init(userID: UUID, eventID: String, chosenAbbreviation: String, confidence: Int) {
        self.userID = userID
        self.eventID = eventID
        self.chosenAbbreviation = chosenAbbreviation
        self.confidence = confidence
    }
}

/// Where somebody stands for a week. Computed server-side from the picks and
/// the results, so it cannot disagree with them.
public struct PickemStanding: Identifiable, Hashable, Sendable {
    public let userID: UUID
    public let displayName: String
    public let correct: Int
    public let decided: Int
    public let points: Int

    public var id: UUID { userID }

    public init(userID: UUID, displayName: String, correct: Int, decided: Int, points: Int) {
        self.userID = userID
        self.displayName = displayName
        self.correct = correct
        self.decided = decided
        self.points = points
    }
}
