import Foundation

/// A trophy in the league's case.
///
/// ESPN has no history for this league — it was created for 2026, and every
/// earlier season returns 404 — so there is nothing to import. The case starts
/// empty and fills up as trophies are earned.
public struct Trophy: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let season: Int
    /// Nil for a season-long award; set for a weekly one.
    public let week: Int?
    public let teamID: Int
    public let kind: String
    public let title: String
    public let detail: String?
    public let awardedAt: Date

    public init(
        id: UUID,
        season: Int,
        week: Int?,
        teamID: Int,
        kind: String,
        title: String,
        detail: String?,
        awardedAt: Date
    ) {
        self.id = id
        self.season = season
        self.week = week
        self.teamID = teamID
        self.kind = kind
        self.title = title
        self.detail = detail
        self.awardedAt = awardedAt
    }
}
