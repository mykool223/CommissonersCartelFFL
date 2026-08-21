import Foundation
import Observation
import CartelCore

@Observable
@MainActor
final class NewsFeedViewModel {
    private(set) var state: Loadable<[NewsPost]> = .idle

    /// `showSpinner` is false for pull-to-refresh, so the existing feed stays
    /// on screen instead of collapsing into a spinner.
    func load(using environment: AppEnvironment, showSpinner: Bool = true) async {
        if showSpinner, state.isInitialLoad { state = .loading }
        let season = environment.season
        let content = environment.content
        if let result = await loadState({ try await content.newsPosts(season: season, limit: 50) }) {
            state = result
        }
    }
}
