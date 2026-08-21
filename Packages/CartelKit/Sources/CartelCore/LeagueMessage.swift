import Foundation

/// A message in the league thread.
public struct LeagueMessage: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let authorID: UUID
    public let authorName: String
    public let body: String
    public let createdAt: Date

    public init(id: UUID, authorID: UUID, authorName: String, body: String, createdAt: Date) {
        self.id = id
        self.authorID = authorID
        self.authorName = authorName
        self.body = body
        self.createdAt = createdAt
    }

    /// True when the signed-in member wrote it, so the UI can align it and
    /// offer to delete it.
    public func isMine(_ userID: UUID?) -> Bool {
        guard let userID else { return false }
        return authorID == userID
    }

    public var initials: String {
        let parts = authorName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}

/// The league thread and the one profile field a member may set on themselves.
public protocol LeagueChatRepository: Sendable {
    /// Newest last, so the view can scroll to the bottom.
    func messages(limit: Int) async throws -> [LeagueMessage]
    func post(_ body: String) async throws
    func deleteMessage(id: UUID) async throws

    /// Links the signed-in account to an ESPN member. ESPN publishes no email
    /// addresses, so this cannot be worked out automatically — the member picks
    /// their team once.
    func claimESPNTeam(swid: String) async throws
    /// The SWID the signed-in member has claimed, if any.
    func claimedESPNTeam() async throws -> String?

    /// Creates a poll. Any member may, not only a commissioner.
    ///
    /// Options arrive as typed, blanks included — a form with a fixed number of
    /// boxes normally has some empty. The server drops them before counting.
    func createPoll(question: String, options: [String], closesAt: Date?) async throws

    /// Whether the signed-in account is actually on the league roster.
    ///
    /// Signing in and being a member are different things: anyone can
    /// authenticate, but only invited addresses get a profile, and every
    /// members-only policy keys off that.
    func isLeagueMember() async -> Bool
}

public extension LeagueChatRepository {
    func messages() async throws -> [LeagueMessage] {
        try await messages(limit: 200)
    }
}
