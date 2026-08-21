import Foundation
import Observation
import CartelCore

@Observable
@MainActor
final class NewsFeedViewModel {
    private(set) var state: Loadable<[NewsPost]> = .idle
    /// Player news loads separately: it is secondary to the league's own
    /// posts, and the publisher being down should not empty the tab.
    private(set) var playerNews: [PlayerNews] = []

    /// `showSpinner` is false for pull-to-refresh, so the existing feed stays
    /// on screen instead of collapsing into a spinner.
    func load(using environment: AppEnvironment, showSpinner: Bool = true) async {
        if showSpinner, state.isInitialLoad { state = .loading }
        let season = environment.season
        let content = environment.content

        // Started first so the two fetches overlap. A Task rather than
        // `async let` because loadState is MainActor-isolated, and `async let`
        // would be reading its result from a nonisolated context.
        //
        // The failure is deliberately swallowed: outside news is a
        // nice-to-have, so a publisher being down leaves the section empty
        // rather than replacing the whole tab with an error nobody can act on.
        let newsTask = Task { try? await content.playerNews() }

        if let result = await loadState({ try await content.newsPosts(season: season, limit: 50) }) {
            state = result
        }
        playerNews = await newsTask.value ?? []
    }
}
