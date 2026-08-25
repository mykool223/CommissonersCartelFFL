import Foundation
import Observation

@Observable
@MainActor
final class CoachViewModel {
    struct Turn: Identifiable {
        let id = UUID()
        let text: String
        let isCoach: Bool
    }

    private(set) var turns: [Turn] = []
    private(set) var isBusy = false
    private var hasLoadedHistory = false

    /// Brings back what was said before. The conversation lives on the server,
    /// so it survives closing the app and follows a member between devices.
    func loadHistory(using environment: AppEnvironment) async {
        guard !hasLoadedHistory, environment.auth != nil else { return }
        hasLoadedHistory = true
        guard let history = try? await environment.content.coachHistory(limit: 100),
              !history.isEmpty else { return }
        // Anything already typed this session stays at the end, where it was.
        turns = history.map { Turn(text: $0.text, isCoach: $0.isCoach) } + turns
    }

    func ask(_ question: String, using environment: AppEnvironment) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }

        turns.append(Turn(text: trimmed, isCoach: false))
        isBusy = true
        defer { isBusy = false }

        turns.append(Turn(text: await answer(to: trimmed, using: environment), isCoach: true))
    }

    private func answer(to question: String, using environment: AppEnvironment) async -> String {
        guard
            let url = environment.configuration.supabaseURL?
                .appending(path: "/functions/v1/coach"),
            // The member's own token, not the anon key: the function answers
            // about whoever is asking, so it has to know who that is.
            let token = await environment.auth?.accessToken()
        else {
            return "Sign in first, under Settings."
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(environment.configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["question": question])

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            // The function gives a readable reason for every refusal, so show
            // it rather than a generic failure.
            return (body?["answer"] as? String)
                ?? (body?["error"] as? String)
                ?? "No answer came back."
        } catch {
            return "Coach Landry isn't answering just now."
        }
    }
}
