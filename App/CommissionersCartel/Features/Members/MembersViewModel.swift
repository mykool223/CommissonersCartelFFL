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
        /// Nil when Supabase has no bio for this team, or is unreachable.
        var bio: TeamBio?
        /// Where the league's published power ranking puts them. Preferred
        /// over ESPN's playoff seed, which before a ball is kicked is not a
        /// ranking at all — it had the commissioner twelfth while the power
        /// ranking had him fourth, which reads as one of them being broken.
        var powerRank: Int?

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
        let content = environment.content
        let result = await loadState { () -> [Group] in
            async let league = leagueData.league()
            async let managers = leagueData.managers()
            async let teams = leagueData.teams()
            // Flavour text is a nice-to-have. A Supabase outage should cost us
            // the bios, not the whole members list.
            async let bios = try? await content.teamBios(season: Season.current())
            async let rankings = try? await content.powerRankings(season: Season.current())

            let allTeams = try await teams
            // One lookup per owner id, since a team can be co-owned.
            var teamByOwner: [String: Team] = [:]
            for team in allTeams {
                for owner in team.ownerIDs where teamByOwner[owner] == nil {
                    teamByOwner[owner] = team
                }
            }

            let bioByTeam = await bios ?? [:]
            let rankByTeam = Dictionary(
                uniqueKeysWithValues: (await rankings ?? []).map { ($0.teamID, $0.rank) })
            // Hand the widget the one thing it cannot work out for itself.
            // Done here rather than at claim time so it self-heals: any launch
            // that loads the roster refreshes it.
            await Self.shareClaimedTeam(teams: allTeams, managers: try await managers)
            let entries = try await managers
                .map { manager -> Entry in
                    let team = teamByOwner[manager.id]
                    return Entry(
                        manager: manager,
                        team: team,
                        bio: team.flatMap { bioByTeam[$0.id] },
                        powerRank: team.flatMap { rankByTeam[$0.id] }
                    )
                }
                // Standings order where ESPN gives us one. Before the season
                // starts every seed is absent, so fall back to record and then
                // to name — otherwise the list order is whatever ESPN felt like.
                .sorted { lhs, rhs in
                    // The published ranking first, so the number shown and the
                    // order agree with each other.
                    if let left = lhs.powerRank, let right = rhs.powerRank {
                        return left < right
                    }
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

    /// Records which team belongs to the signed-in member, for the widget.
    ///
    /// The widget runs in its own process with no session, so it cannot ask.
    /// It reads this from the shared app group and fetches the score itself.
    private static func shareClaimedTeam(teams: [Team], managers: [Manager]) async {
        guard let swid = KeychainStore.string(for: .espnSWID)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !swid.isEmpty
        else { return }

        let normalised = swid.uppercased()
        guard let team = teams.first(where: { team in
            team.ownerIDs.contains { $0.uppercased() == normalised }
        }) else { return }

        SharedStore.claimedTeamID = team.id
        SharedStore.claimedTeamName = team.name
    }

    /// Flattened, for the navigation destination lookup.
    var allEntries: [Entry] {
        state.value?.flatMap(\.entries) ?? []
    }
}
