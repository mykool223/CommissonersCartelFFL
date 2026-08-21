import Foundation

/// A headline syndicated from outside the league.
///
/// Holds only the reference — title, excerpt, link — never the article body.
/// Tapping one opens the publisher's page, which is the arrangement an RSS feed
/// implies: they get the traffic, we get the headline.
public struct ExternalArticle: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    /// Machine key for the publisher, e.g. "fantasy_footballers".
    public let sourceKey: String
    /// Display name, e.g. "The Fantasy Footballers".
    public let sourceName: String
    public let title: String
    public let url: URL
    public let excerpt: String?
    public let author: String?
    public let imageURL: URL?
    public let publishedAt: Date

    public init(
        id: UUID,
        sourceKey: String,
        sourceName: String,
        title: String,
        url: URL,
        excerpt: String? = nil,
        author: String? = nil,
        imageURL: URL? = nil,
        publishedAt: Date
    ) {
        self.id = id
        self.sourceKey = sourceKey
        self.sourceName = sourceName
        self.title = title
        self.url = url
        self.excerpt = excerpt
        self.author = author
        self.imageURL = imageURL
        self.publishedAt = publishedAt
    }

    /// How long ago it was published, for the row's byline.
    public func age(asOf now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(publishedAt)
    }

    /// True while the article is inside the freshness window the ingest uses.
    public func isRecent(asOf now: Date = Date(), within hours: Double = 24) -> Bool {
        age(asOf: now) <= hours * 3_600
    }
}
