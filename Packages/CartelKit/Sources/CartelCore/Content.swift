import Foundation

/// A commissioner-authored post: weekly news, power rankings, announcements.
public struct NewsPost: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let title: String
    public let body: String
    public let authorID: UUID?
    public let authorName: String
    /// Week the post is about. Nil for evergreen announcements.
    public let week: Int?
    public let season: Int
    public let coverImageURL: URL?
    public let publishedAt: Date

    public init(
        id: UUID,
        title: String,
        body: String,
        authorID: UUID? = nil,
        authorName: String,
        week: Int? = nil,
        season: Int,
        coverImageURL: URL? = nil,
        publishedAt: Date
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.authorID = authorID
        self.authorName = authorName
        self.week = week
        self.season = season
        self.coverImageURL = coverImageURL
        self.publishedAt = publishedAt
    }

    /// First paragraph, trimmed for list rows.
    public var excerpt: String {
        let firstParagraph = body
            .components(separatedBy: "\n\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard firstParagraph.count > 180 else { return firstParagraph }
        let cutoff = firstParagraph.index(firstParagraph.startIndex, offsetBy: 180)
        return firstParagraph[..<cutoff].trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// A written recap tied to a specific matchup, so it can be shown inline on
/// the matchup screen as well as in the news feed.
public struct Recap: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let season: Int
    public let week: Int
    public let matchupID: Int?
    public let headline: String
    public let body: String
    public let authorName: String
    public let createdAt: Date

    public init(
        id: UUID,
        season: Int,
        week: Int,
        matchupID: Int? = nil,
        headline: String,
        body: String,
        authorName: String,
        createdAt: Date
    ) {
        self.id = id
        self.season = season
        self.week = week
        self.matchupID = matchupID
        self.headline = headline
        self.body = body
        self.authorName = authorName
        self.createdAt = createdAt
    }
}
