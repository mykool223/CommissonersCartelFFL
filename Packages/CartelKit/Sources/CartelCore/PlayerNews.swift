import Foundation

/// A short player-news update: injury, depth chart move, practice report.
///
/// Carries the blurb itself so the app can show it inline. `url` is kept so a
/// reader can go to the publisher for the full analysis, which is deliberately
/// not stored.
public struct PlayerNews: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    /// The publisher's own numeric id, used for deduplication.
    public let sourceID: Int
    public let sourceName: String

    public let playerName: String
    /// "WR", "QB". Nil when the publisher omits it.
    public let position: String?
    /// "JAX", "SF".
    public let team: String?
    public let headshotURL: URL?

    public let headline: String
    public let blurb: String?
    public let url: URL
    public let publishedAt: Date

    public init(
        id: UUID,
        sourceID: Int,
        sourceName: String,
        playerName: String,
        position: String? = nil,
        team: String? = nil,
        headshotURL: URL? = nil,
        headline: String,
        blurb: String? = nil,
        url: URL,
        publishedAt: Date
    ) {
        self.id = id
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.playerName = playerName
        self.position = position
        self.team = team
        self.headshotURL = headshotURL
        self.headline = headline
        self.blurb = blurb
        self.url = url
        self.publishedAt = publishedAt
    }

    /// "WR · JAX", or just one of them, or nil when neither is known.
    public var positionAndTeam: String? {
        let parts = [position, team].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public func isRecent(asOf now: Date = Date(), within hours: Double = 24) -> Bool {
        now.timeIntervalSince(publishedAt) <= hours * 3_600
    }
}
