import Foundation

/// One player on a team for a given week, and what they have scored.
///
/// Deliberately free of ESPN's numbering: the wire format uses integer ids for
/// both the player's position and the slot they are filling, and those ids mean
/// nothing outside ESPN. They are translated once, in `ESPNMapper`, so a change
/// at their end lands in one file rather than in every view that shows a name.
public struct RosterEntry: Identifiable, Hashable, Sendable, Codable {
    public let playerID: Int
    public let name: String
    /// What the player is — "QB", "RB", "D/ST".
    public let position: String
    /// Where they are being played this week — "QB", "FLEX", "Bench".
    /// Not the same thing: a running back in the flex is an RB in FLEX.
    public let slot: String
    /// False for the bench and for injured reserve. Only starters score.
    public let isStarter: Bool
    public let points: Double

    public var id: Int { playerID }

    public init(
        playerID: Int,
        name: String,
        position: String,
        slot: String,
        isStarter: Bool,
        points: Double
    ) {
        self.playerID = playerID
        self.name = name
        self.position = position
        self.slot = slot
        self.isStarter = isStarter
        self.points = points
    }
}
