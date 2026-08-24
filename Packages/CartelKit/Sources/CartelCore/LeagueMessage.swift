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
/// One person's reaction to one message.
public struct MessageReaction: Hashable, Sendable {
    public let messageID: UUID
    public let userID: UUID
    public let emoji: String

    public init(messageID: UUID, userID: UUID, emoji: String) {
        self.messageID = messageID
        self.userID = userID
        self.emoji = emoji
    }
}

/// Reactions on one message, folded into what a row needs to draw.
public struct ReactionSummary: Identifiable, Hashable, Sendable {
    public let emoji: String
    public let count: Int
    public let isMine: Bool

    public var id: String { emoji }

    public init(emoji: String, count: Int, isMine: Bool) {
        self.emoji = emoji
        self.count = count
        self.isMine = isMine
    }

    /// The set offered. A thumbs-down is the point, not an oversight.
    public static let palette = ["👍", "👎", "😂", "🔥", "💀"]

    public static func summarise(
        _ all: [MessageReaction],
        messageID: UUID,
        me: UUID?
    ) -> [ReactionSummary] {
        Dictionary(grouping: all.filter { $0.messageID == messageID }, by: \.emoji)
            .map { emoji, rows in
                ReactionSummary(
                    emoji: emoji,
                    count: rows.count,
                    isMine: me.map { id in rows.contains { $0.userID == id } } ?? false
                )
            }
            .sorted { $0.count > $1.count }
    }
}

public protocol LeagueChatRepository: Sendable {
    /// Newest last, so the view can scroll to the bottom.
    func messages(limit: Int) async throws -> [LeagueMessage]
    func post(_ body: String) async throws
    func deleteMessage(id: UUID) async throws

    /// Every reaction the caller may see. Small league, small table.
    func reactions() async throws -> [MessageReaction]
    func addReaction(messageID: UUID, emoji: String) async throws
    func removeReaction(messageID: UUID, emoji: String) async throws

    /// Every message you are party to. Row level security returns only those.
    func directMessages() async throws -> [DirectMessage]
    func sendDirectMessage(to recipientID: UUID, body: String) async throws
    /// Display names, for conversation titles.
    func memberNames() async throws -> [UUID: String]

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
