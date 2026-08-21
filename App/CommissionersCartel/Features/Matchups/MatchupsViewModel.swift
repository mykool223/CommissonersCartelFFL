import Foundation
import Observation
import CartelCore

@Observable
@MainActor
final class MatchupsViewModel {
    /// Everything one week's screen needs, fetched together so the UI never
    /// renders scores before it can name the teams.
    struct Board {
        let league: League
        let teamsByID: [Int: Team]
        let matchups: [Matchup]
        let recaps: [Recap]

        func team(_ id: Int) -> Team? { teamsByID[id] }

        func recap(for matchup: Matchup) -> Recap? {
            recaps.first { $0.matchupID == matchup.id }
        }
    }

    private(set) var state: Loadable<Board> = .idle
    /// Nil until the league's current week is known, then user-controlled.
    var selectedWeek: Int?

    func load(using environment: AppEnvironment, showSpinner: Bool = true) async {
        if showSpinner, state.isInitialLoad { state = .loading }

        let leagueData = environment.leagueData
        let content = environment.content
        let season = environment.season
        let requestedWeek = selectedWeek

        let result = await loadState { () -> Board in
            let league = try await leagueData.league()
            let week = requestedWeek ?? league.currentWeek

            // Matchups and recaps are independent, so overlap them.
            async let teams = leagueData.teams()
            async let matchups = leagueData.matchups(week: week)
            async let recaps = content.recaps(season: season, week: week)

            return Board(
                league: league,
                teamsByID: Dictionary(
                    uniqueKeysWithValues: try await teams.map { ($0.id, $0) }
                ),
                matchups: try await matchups,
                // A missing recap is not a reason to fail the whole screen.
                recaps: (try? await recaps) ?? []
            )
        }

        if let result {
            state = result
            if selectedWeek == nil, case let .loaded(board) = result {
                selectedWeek = board.league.currentWeek
            }
        }
    }

    func selectWeek(_ week: Int, using environment: AppEnvironment) async {
        guard week != selectedWeek else { return }
        selectedWeek = week
        await load(using: environment, showSpinner: false)
    }
}
