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

    public init(id: UUID, senderID: UUID, recipientID: UUID, body: String, createdAt: Date) {
        self.id = id
        self.senderID = senderID
        self.recipientID = recipientID
        self.body = body
        self.createdAt = createdAt
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

    public var id: UUID { userID }

    public init(userID: UUID, displayName: String, lastMessage: String, lastAt: Date) {
        self.userID = userID
        self.displayName = displayName
        self.lastMessage = lastMessage
        self.lastAt = lastAt
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
                    lastAt: last.createdAt
                )
            }
            .sorted { $0.lastAt > $1.lastAt }
    }
}
