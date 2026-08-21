import Foundation
import Observation
import CartelCore

@Observable
@MainActor
final class NewsFeedViewModel {
    private(set) var state: Loadable<[NewsPost]> = .idle
    /// Outside headlines load separately: they are secondary to the league's
    /// own posts, and a publisher feed being down should not empty the tab.
    private(set) var articles: [ExternalArticle] = []

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
        let articlesTask = Task { try? await content.externalArticles() }

        if let result = await loadState({ try await content.newsPosts(season: season, limit: 50) }) {
            state = result
        }
        articles = await articlesTask.value ?? []
    }
}
