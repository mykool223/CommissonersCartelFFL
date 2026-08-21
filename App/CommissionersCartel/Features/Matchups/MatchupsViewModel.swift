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
        /// The week before, kept only so the recap can compute "most improved".
        let previousMatchups: [Matchup]
        let recaps: [Recap]
        let week: Int

        func team(_ id: Int) -> Team? { teamsByID[id] }

        func recap(for matchup: Matchup) -> Recap? {
            recaps.first { $0.matchupID == matchup.id }
        }

        var awards: [WeeklyAward] {
            WeeklyAwards.compute(matchups: matchups, previousWeek: previousMatchups)
        }

        /// Teams in table order, split by division when the league has them.
        struct StandingsGroup: Identifiable {
            let division: Division?
            let teams: [Team]
            var id: Int { division?.id ?? -1 }
            var title: String? { division?.name }
        }

        var standings: [StandingsGroup] {
            let ordered = teamsByID.values.sorted(by: Board.ranks)
            guard league.hasDivisions else {
                return [StandingsGroup(division: nil, teams: ordered)]
            }
            var groups = league.divisions.map { division in
                StandingsGroup(
                    division: division,
                    teams: ordered.filter { $0.divisionID == division.id }
                )
            }
            // A team ESPN did not place in a division would otherwise be
            // missing from the table entirely.
            let known = Set(league.divisions.map(\.id))
            let orphans = ordered.filter { team in
                guard let id = team.divisionID else { return true }
                return !known.contains(id)
            }
            if !orphans.isEmpty {
                groups.append(StandingsGroup(division: nil, teams: orphans))
            }
            return groups.filter { !$0.teams.isEmpty }
        }

        /// ESPN's seed when it has one; before the season starts every seed is
        /// absent, so fall back to record, then points, then name.
        private static func ranks(_ lhs: Team, _ rhs: Team) -> Bool {
            switch (lhs.playoffSeed, rhs.playoffSeed) {
            case let (l?, r?): return l < r
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil):
                if lhs.record.winPercentage != rhs.record.winPercentage {
                    return lhs.record.winPercentage > rhs.record.winPercentage
                }
                if lhs.record.pointsFor != rhs.record.pointsFor {
                    return lhs.record.pointsFor > rhs.record.pointsFor
                }
                return lhs.name < rhs.name
            }
        }
    }

    private(set) var state: Loadable<Board> = .idle
    /// Nil until the league's current week is known, then user-controlled.
    var selectedWeek: Int?

    /// Pull-to-refresh. Drops the ESPN cache first, so this actually goes to
    /// the network rather than replaying a response up to the cache TTL old.
    func refresh(using environment: AppEnvironment) async {
        await environment.leagueData.refresh()
        await load(using: environment, showSpinner: false)
    }

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
            // Free: the same cached ESPN payload holds the whole season.
            async let previous = week > 1 ? leagueData.matchups(week: week - 1) : []
            async let recaps = content.recaps(season: season, week: week)

            return Board(
                league: league,
                teamsByID: Dictionary(
                    uniqueKeysWithValues: try await teams.map { ($0.id, $0) }
                ),
                matchups: try await matchups,
                previousMatchups: (try? await previous) ?? [],
                // A missing recap is not a reason to fail the whole screen.
                recaps: (try? await recaps) ?? [],
                week: week
            )
        }

        if let result {
            state = result
            if selectedWeek == nil, case let .loaded(board) = result {
                selectedWeek = board.league.currentWeek
            }
        }
    }

    /// Steps back to the last week that was actually played.
    ///
    /// A recap is about what happened, and the week in progress has happened to
    /// nobody yet — landing on it shows an empty screen every Sunday. Called
    /// when the recap section opens; a no-op once there is something to show,
    /// and in week 1 where there is no earlier week to fall back to.
    func showMostRecentPlayedWeek(using environment: AppEnvironment) async {
        guard case let .loaded(board) = state,
              board.awards.isEmpty,
              board.week > 1
        else { return }
        await selectWeek(board.week - 1, using: environment)
    }

    func selectWeek(_ week: Int, using environment: AppEnvironment) async {
        guard week != selectedWeek else { return }
        selectedWeek = week
        await load(using: environment, showSpinner: false)
    }
}
