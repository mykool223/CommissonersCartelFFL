import Foundation

/// A player news item from FantasyPros, with their read on what it means.
///
/// The headline and a short extract of their analysis are shown; the full
/// piece is a tap away on their site. Their writing is theirs, and a link is
/// the honest way to pass somebody else's work along.
public struct AnalysisItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let summary: String?
    /// What it means for fantasy, in their words.
    public let impact: String?
    public let link: URL
    public let playerName: String?
    public let team: String?
    public let publishedAt: Date

    public init(
        id: UUID, title: String, summary: String?, impact: String?,
        link: URL, playerName: String?, team: String?, publishedAt: Date
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.impact = impact
        self.link = link
        self.playerName = playerName
        self.team = team
        self.publishedAt = publishedAt
    }
}
