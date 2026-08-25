import Foundation

/// An article from FantasyPros.
///
/// Their API has no articles endpoint — only single-player news, which is the
/// same material the Fantasy Footballers feed already carries — so these come
/// from the RSS feed they publish for the purpose.
///
/// The title, author and excerpt are shown; the piece itself opens on their
/// site. Somebody else's writing belongs where they published it.
public struct AnalysisItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let excerpt: String?
    public let link: URL
    public let author: String?
    /// Players and topics the article is filed under, site furniture removed.
    public let categories: [String]
    public let publishedAt: Date

    public init(
        id: UUID, title: String, excerpt: String?, link: URL,
        author: String?, categories: [String], publishedAt: Date
    ) {
        self.id = id
        self.title = title
        self.excerpt = excerpt
        self.link = link
        self.author = author
        self.categories = categories
        self.publishedAt = publishedAt
    }
}
