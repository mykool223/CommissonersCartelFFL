import Foundation
import Observation
import CartelCore

@Observable
@MainActor
final class DirectMessagesViewModel {
    private(set) var messages: [DirectMessage] = []
    private(set) var conversations: [Conversation] = []
    private(set) var isLoading = false

    func load(using environment: AppEnvironment) async {
        guard let chat = environment.chat, environment.isSignedIn else {
            messages = []
            conversations = []
            return
        }
        isLoading = true
        defer { isLoading = false }

        messages = (try? await chat.directMessages()) ?? []
        // Names are cosmetic; losing them should not lose the conversation.
        let names = (try? await chat.memberNames()) ?? [:]
        conversations = Conversation.fold(
            messages, names: names, me: environment.session?.userID
        )
    }

    /// Opening a conversation is what marks it read.
    ///
    /// Only their messages are touched — row level security allows nothing
    /// else — and it is deliberately quiet: failing to clear a mark is a
    /// nuisance, not something to interrupt somebody reading with.
    func markRead(with userID: UUID, using environment: AppEnvironment) async {
        guard let chat = environment.chat,
              conversations.first(where: { $0.userID == userID })?.unread ?? 0 > 0
        else { return }
        try? await chat.markConversationRead(with: userID)
        await load(using: environment)
        NotificationCenter.default.post(name: .directMessagesChanged, object: nil)
    }

    func send(to recipientID: UUID, body: String, using environment: AppEnvironment) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let chat = environment.chat else { return }
        try? await chat.sendDirectMessage(to: recipientID, body: trimmed)
        await load(using: environment)
        NotificationCenter.default.post(name: .directMessagesChanged, object: nil)
    }

    /// An empty conversation, so a first message has somewhere to go.
    func conversation(with userID: UUID, named name: String) -> Conversation {
        conversations.first { $0.userID == userID }
            ?? Conversation(userID: userID, displayName: name, lastMessage: "", lastAt: .now)
    }
}
