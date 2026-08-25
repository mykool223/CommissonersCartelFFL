import Foundation

/// One line of a member's conversation with the coach.
///
/// The conversation is kept server-side rather than in the app, so it survives
/// closing the app and is the same on every device somebody signs in on.
public struct CoachMessage: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// Monotonic within a member's conversation. Question and answer are
    /// written together and share a timestamp, so time alone cannot order them.
    public let sequence: Int
    public let isCoach: Bool
    public let text: String
    public let createdAt: Date

    public init(id: UUID, sequence: Int, isCoach: Bool, text: String, createdAt: Date) {
        self.id = id
        self.sequence = sequence
        self.isCoach = isCoach
        self.text = text
        self.createdAt = createdAt
    }
}
