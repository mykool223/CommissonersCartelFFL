import Foundation

/// Read-only league data. Backed by ESPN in production and by
/// `MockLeagueDataSource` in previews and tests.
///
/// Every screen depends on this protocol rather than on `CartelESPN` directly,
/// so the ESPN scraping layer can be replaced without touching the UI.
public protocol LeagueDataSource: Sendable {
    func league() async throws -> League
    func managers() async throws -> [Manager]
    func teams() async throws -> [Team]
    func matchups(week: Int) async throws -> [Matchup]
}

/// League-authored content. Backed by Supabase in production.
public protocol ContentRepository: Sendable {
    func newsPosts(season: Int, limit: Int) async throws -> [NewsPost]
    func recaps(season: Int, week: Int) async throws -> [Recap]
    func polls(season: Int) async throws -> [Poll]

    /// Records the caller's vote. Replaces any previous vote on the same poll.
    func vote(pollID: UUID, optionID: UUID) async throws
}

public extension ContentRepository {
    func newsPosts(season: Int) async throws -> [NewsPost] {
        try await newsPosts(season: season, limit: 50)
    }
}

/// Errors surfaced to the UI. Anything lower-level gets wrapped in `.transport`
/// or `.decoding` so views only ever switch over these cases.
public enum CartelError: Error, Sendable {
    /// The league is private and the request had no valid ESPN credentials.
    case notAuthorized
    /// ESPN or Supabase returned a non-2xx status.
    case server(statusCode: Int, message: String?)
    /// The response parsed but did not contain what we expected. Usually means
    /// ESPN changed their payload shape.
    case decoding(String)
    /// URLSession failed: offline, DNS, TLS, timeout.
    case transport(String)
    /// Configuration is missing or malformed, e.g. no league id set.
    case notConfigured(String)
}

extension CartelError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "This league is private. Add your ESPN credentials in Settings."
        case let .server(statusCode, message):
            return message ?? "The server returned an error (\(statusCode))."
        case let .decoding(detail):
            return "Couldn't read the response. \(detail)"
        case let .transport(detail):
            return "Network problem. \(detail)"
        case let .notConfigured(detail):
            return "Not set up yet. \(detail)"
        }
    }
}
