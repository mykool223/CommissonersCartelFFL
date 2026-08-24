import Foundation
import Observation
import CartelCore

@Observable
@MainActor
final class TrophyCaseViewModel {
    /// A trophy paired with the team that won it, which lives in ESPN's data.
    struct Entry: Identifiable {
        let trophy: Trophy
        let team: Team?

        var id: UUID { trophy.id }
    }

    private(set) var state: Loadable<[Entry]> = .idle

    func load(using environment: AppEnvironment) async {
        if state.isInitialLoad { state = .loading }

        let content = environment.content
        let leagueData = environment.leagueData
        let season = environment.season

        let result = await loadState { () -> [Entry] in
            let trophies = try await content.trophies(season: season)
            guard !trophies.isEmpty else { return [] }
            // Only worth an ESPN round trip once there is something to label.
            let teams = try await leagueData.teams()
            let byID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
            return trophies.map { Entry(trophy: $0, team: byID[$0.teamID]) }
        }

        if let result { state = result }
    }
}
