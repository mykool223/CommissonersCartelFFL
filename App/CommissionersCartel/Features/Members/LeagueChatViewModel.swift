import Foundation
import Observation
import CartelCore

@Observable
@MainActor
final class LeagueChatViewModel {
    private(set) var messages: [LeagueMessage] = []
    private(set) var reactions: [MessageReaction] = []
    private(set) var memberNames: [String] = []
    private(set) var isLoading = false
    private(set) var isSending = false
    var postError: String?

    /// Adds or removes one reaction, then re-reads. Re-reading rather than
    /// patching locally keeps the count honest when two people react at once.
    func react(
        to message: LeagueMessage,
        emoji: String,
        isMine: Bool,
        using environment: AppEnvironment
    ) async {
        guard let chat = environment.chat else { return }
        if isMine {
            try? await chat.removeReaction(messageID: message.id, emoji: emoji)
        } else {
            try? await chat.addReaction(messageID: message.id, emoji: emoji)
        }
        reactions = (try? await chat.reactions()) ?? reactions
    }

    func load(using environment: AppEnvironment) async {
        guard let chat = environment.chat, environment.isSignedIn else {
            messages = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        messages = (try? await chat.messages()) ?? []
        // A reaction failure must not cost the thread itself.
        reactions = (try? await chat.reactions()) ?? []
        memberNames = ((try? await chat.memberNames()) ?? [:]).values.sorted()
    }

    /// Returns the text to put back in the composer when the post failed, or
    /// nil on success.
    func post(_ body: String, using environment: AppEnvironment) async -> String? {
        guard let chat = environment.chat else { return body }
        postError = nil
        isSending = true
        defer { isSending = false }

        do {
            try await chat.post(body)
            await load(using: environment)
            return nil
        } catch let error as CartelError {
            postError = error.errorDescription ?? "Couldn't post that."
            return body
        } catch {
            postError = error.localizedDescription
            return body
        }
    }

    func delete(_ message: LeagueMessage, using environment: AppEnvironment) async {
        guard let chat = environment.chat else { return }
        // Removed locally first so the tap feels immediate; a failed delete
        // reappears on the next load.
        messages.removeAll { $0.id == message.id }
        try? await chat.deleteMessage(id: message.id)
        await load(using: environment)
    }
}
