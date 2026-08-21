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

    /// Entries grouped under a division heading. A league without divisions
    /// produces a single unnamed group, so the view renders one flat list
    /// without needing a separate code path.
    struct Group: Identifiable {
        let division: Division?
        let entries: [Entry]

        var id: Int { division?.id ?? -1 }
        var title: String? { division?.name }
    }

    private(set) var state: Loadable<[Group]> = .idle

    /// Pull-to-refresh. Drops the ESPN cache first, so this actually goes to
    /// the network rather than replaying a response up to the cache TTL old.
    func refresh(using environment: AppEnvironment) async {
        await environment.leagueData.refresh()
        await load(using: environment, showSpinner: false)
    }

    func load(using environment: AppEnvironment, showSpinner: Bool = true) async {
        if showSpinner, state.isInitialLoad { state = .loading }

        let leagueData = environment.leagueData
        let result = await loadState { () -> [Group] in
            async let league = leagueData.league()
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

            let entries = try await managers
                .map { Entry(manager: $0, team: teamByOwner[$0.id]) }
                // Standings order where ESPN gives us one. Before the season
                // starts every seed is absent, so fall back to record and then
                // to name — otherwise the list order is whatever ESPN felt like.
                .sorted { lhs, rhs in
                    switch (lhs.team?.playoffSeed, rhs.team?.playoffSeed) {
                    case let (l?, r?):
                        return l < r
                    case (nil, _?):
                        return false
                    case (_?, nil):
                        return true
                    case (nil, nil):
                        let left = lhs.team?.record, right = rhs.team?.record
                        let leftPct = left?.winPercentage ?? -1
                        let rightPct = right?.winPercentage ?? -1
                        if leftPct != rightPct { return leftPct > rightPct }
                        let leftFor = left?.pointsFor ?? 0
                        let rightFor = right?.pointsFor ?? 0
                        if leftFor != rightFor { return leftFor > rightFor }
                        return lhs.manager.fullName < rhs.manager.fullName
                    }
                }

            let divisions = try await league.divisions
            guard divisions.count > 1 else {
                return [Group(division: nil, entries: entries)]
            }

            // Managers whose team ESPN did not place in a division would
            // otherwise vanish from a grouped list entirely.
            var grouped = divisions.map { division in
                Group(
                    division: division,
                    entries: entries.filter { $0.team?.divisionID == division.id }
                )
            }
            let knownIDs = Set(divisions.map(\.id))
            let ungrouped = entries.filter { entry in
                guard let id = entry.team?.divisionID else { return true }
                return !knownIDs.contains(id)
            }
            if !ungrouped.isEmpty {
                grouped.append(Group(division: nil, entries: ungrouped))
            }
            return grouped.filter { !$0.entries.isEmpty }
        }

        if let result { state = result }
    }

    /// Flattened, for the navigation destination lookup.
    var allEntries: [Entry] {
        state.value?.flatMap(\.entries) ?? []
    }
}
