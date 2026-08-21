import Foundation
import Observation
import CartelCore

@Observable
@MainActor
final class MembersViewModel {
    /// A manager paired with the team they own. ESPN keeps these in separate
    /// arrays linked by SWID, so the join happens once here.
    struct Entry: Identifiable {
        let manager: Manager
        let team: Team?

        var id: String { manager.id }
    }

    private(set) var state: Loadable<[Entry]> = .idle

    func load(using environment: AppEnvironment, showSpinner: Bool = true) async {
        if showSpinner, state.isInitialLoad { state = .loading }

        let leagueData = environment.leagueData
        let result = await loadState { () -> [Entry] in
            async let managers = leagueData.managers()
            async let teams = leagueData.teams()

            let allTeams = try await teams
            // One lookup per owner id, since a team can be co-owned.
            var teamByOwner: [String: Team] = [:]
            for team in allTeams {
                for owner in team.ownerIDs where teamByOwner[owner] == nil {
                    teamByOwner[owner] = team
                }
            }

            return try await managers
                .map { Entry(manager: $0, team: teamByOwner[$0.id]) }
                // Standings order, with team-less members last.
                .sorted { lhs, rhs in
                    switch (lhs.team?.playoffSeed, rhs.team?.playoffSeed) {
                    case let (l?, r?): return l < r
                    case (nil, _?): return false
                    case (_?, nil): return true
                    case (nil, nil): return lhs.manager.fullName < rhs.manager.fullName
                    }
                }
        }

        if let result { state = result }
    }
}
