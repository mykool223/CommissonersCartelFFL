import Foundation

/// A private message between two members.
///
/// Visible only to the two people in the conversation — enforced in Postgres,
/// not in the app. A member reading somebody else's messages has to be
/// impossible rather than merely un-navigable.
public struct DirectMessage: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let senderID: UUID
    public let recipientID: UUID
    public let body: String
    public let createdAt: Date
    /// When the recipient opened the conversation containing it. Nil until
    /// they have, which is what the unread marks are counting.
    public let readAt: Date?

    public init(
        id: UUID, senderID: UUID, recipientID: UUID, body: String,
        createdAt: Date, readAt: Date? = nil
    ) {
        self.id = id
        self.senderID = senderID
        self.recipientID = recipientID
        self.body = body
        self.createdAt = createdAt
        self.readAt = readAt
    }

    /// Unread, from the point of view of whoever is asking. A message you sent
    /// is never unread to you, however long the other person leaves it.
    public func isUnread(for me: UUID?) -> Bool {
        readAt == nil && recipientID == me
    }

    /// The other party, whichever end of it you are.
    public func counterpart(of me: UUID?) -> UUID {
        senderID == me ? recipientID : senderID
    }
}

/// One conversation, folded down to what an inbox row needs.
public struct Conversation: Identifiable, Hashable, Sendable {
    public let userID: UUID
    public let displayName: String
    public let lastMessage: String
    public let lastAt: Date
    /// How many of theirs you have not opened.
    public let unread: Int

    public var id: UUID { userID }

    public init(
        userID: UUID, displayName: String, lastMessage: String,
        lastAt: Date, unread: Int = 0
    ) {
        self.userID = userID
        self.displayName = displayName
        self.lastMessage = lastMessage
        self.lastAt = lastAt
        self.unread = unread
    }

    /// Groups a flat list into conversations, most recently active first.
    public static func fold(
        _ messages: [DirectMessage],
        names: [UUID: String],
        me: UUID?
    ) -> [Conversation] {
        Dictionary(grouping: messages) { $0.counterpart(of: me) }
            .compactMap { userID, thread -> Conversation? in
                guard let last = thread.max(by: { $0.createdAt < $1.createdAt }) else { return nil }
                return Conversation(
                    userID: userID,
                    displayName: names[userID] ?? "Someone",
                    lastMessage: last.body,
                    lastAt: last.createdAt,
                    unread: thread.count { $0.isUnread(for: me) }
                )
            }
            .sorted { $0.lastAt > $1.lastAt }
    }

    /// Everything waiting across every conversation, for the tab mark.
    public static func unreadCount(_ conversations: [Conversation]) -> Int {
        conversations.reduce(0) { $0 + $1.unread }
    }
}
