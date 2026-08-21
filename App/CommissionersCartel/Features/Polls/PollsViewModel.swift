import Foundation
import Observation
import CartelCore

@Observable
@MainActor
final class PollsViewModel {
    private(set) var state: Loadable<[Poll]> = .idle
    /// Surfaced as an alert when a vote fails to save.
    var voteError: String?

    func load(using environment: AppEnvironment, showSpinner: Bool = true) async {
        if showSpinner, state.isInitialLoad { state = .loading }
        let content = environment.content
        let season = environment.season
        if let result = await loadState({ try await content.polls(season: season) }) {
            state = result
        }
    }

    /// Applies the vote locally first so the bars move immediately, then saves.
    /// On failure the optimistic change is rolled back and the user is told.
    func vote(pollID: UUID, optionID: UUID, using environment: AppEnvironment) async {
        guard case let .loaded(polls) = state,
              let index = polls.firstIndex(where: { $0.id == pollID })
        else { return }

        let previous = polls
        var optimistic = polls
        optimistic[index] = polls[index].applyingVote(optionID: optionID)
        state = .loaded(optimistic)

        do {
            try await environment.content.vote(pollID: pollID, optionID: optionID)
        } catch {
            state = .loaded(previous)
            voteError = (error as? CartelError)?.errorDescription
                ?? "Couldn't save your vote. Try again."
            return
        }

        // Re-read so the tally reflects everyone else's votes too, not just ours.
        await load(using: environment, showSpinner: false)
    }
}
