import Foundation
import Observation
import CartelCore

@Observable
@MainActor
final class LeagueChatViewModel {
    private(set) var messages: [LeagueMessage] = []
    private(set) var isLoading = false
    private(set) var isSending = false
    var postError: String?

    func load(using environment: AppEnvironment) async {
        guard let chat = environment.chat, environment.isSignedIn else {
            messages = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        messages = (try? await chat.messages()) ?? []
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
