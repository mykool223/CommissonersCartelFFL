import Foundation

/// Where a team sits in the league's power ranking.
///
/// Read off FantasyPros' league analyzer and stored, rather than computed:
/// their score grades a whole roster with a value model their public API does
/// not expose, and three attempts to reproduce its ordering came out barely
/// better than shuffling. Copying the real thing beats approximating it badly.
public struct PowerRanking: Identifiable, Hashable, Sendable {
    public let season: Int
    /// 0 for the preseason ranking; otherwise the week it followed.
    public let week: Int
    public let teamID: Int
    public let teamName: String
    public let score: Double
    public let rank: Int
    /// "out of 100" — their scale, not ours, so it is stated rather than
    /// assumed.
    public let unit: String?
    public let computedAt: Date

    public var id: Int { teamID }

    public init(
        season: Int, week: Int, teamID: Int, teamName: String,
        score: Double, rank: Int, unit: String?, computedAt: Date
    ) {
        self.season = season
        self.week = week
        self.teamID = teamID
        self.teamName = teamName
        self.score = score
        self.rank = rank
        self.unit = unit
        self.computedAt = computedAt
    }
}
