import Foundation
import CartelCore

/// Translates ESPN wire types into the app's domain models.
///
/// Kept separate from the networking so it can be unit-tested against saved
/// JSON fixtures with no network involved.
enum ESPNMapper {
    static func league(from dto: ESPNLeagueResponse, fallbackSeason: Int) -> League {
        let regularSeasonWeeks = dto.settings?.scheduleSettings?.matchupPeriodCount ?? 14
        // `currentMatchupPeriod` runs ahead of reality once the season ends, so
        // clamp it to the schedule length we know about.
        let current = dto.status?.currentMatchupPeriod ?? 1
        let divisions = (dto.settings?.scheduleSettings?.divisions ?? []).map {
            Division(id: $0.id, name: $0.name ?? "Division \($0.id + 1)", size: $0.size ?? 0)
        }
        return League(
            id: String(dto.id),
            name: dto.settings?.name ?? "Fantasy League",
            season: dto.seasonId ?? fallbackSeason,
            currentWeek: max(1, current),
            regularSeasonWeeks: regularSeasonWeeks,
            teamCount: dto.teams?.count ?? 0,
            divisions: divisions
        )
    }

    static func managers(from dto: ESPNLeagueResponse) -> [Manager] {
        (dto.members ?? []).map { member in
            Manager(
                id: member.id,
                displayName: member.displayName ?? member.id,
                firstName: member.firstName,
                lastName: member.lastName,
                // ESPN omits isLeagueManager from this payload entirely — it is
                // absent rather than false, so nobody is ever flagged. Supabase
                // (profiles.is_commissioner) is the authoritative source; this
                // only fills in when ESPN happens to supply it.
                isCommissioner: member.isLeagueManager ?? false
            )
        }
    }

    /// - Parameter imageProxyBase: when set, logos that ESPN serves behind
    ///   authentication are rewritten to go through the proxy, which holds the
    ///   cookies. Public CDN logos are left alone.
    static func teams(from dto: ESPNLeagueResponse, imageProxyBase: URL? = nil) -> [Team] {
        (dto.teams ?? []).map { team in
            Team(
                id: team.id,
                name: displayName(for: team),
                abbreviation: team.abbrev ?? "T\(team.id)",
                logoURL: logoURL(for: team, imageProxyBase: imageProxyBase),
                ownerIDs: ownerIDs(for: team),
                record: record(from: team.record?.overall),
                // ESPN reports 0 before the season starts, not null. Treated as
                // a real seed it renders as "#0" and makes the standings sort
                // meaningless, since every team ties at zero.
                playoffSeed: (team.playoffSeed ?? 0) > 0 ? team.playoffSeed : nil,
                divisionID: team.divisionId
            )
        }
    }

    /// ESPN serves team logos from two places, and they behave differently.
    ///
    /// Logos a manager uploaded live on `mystique-api.fantasy.espn.com` and
    /// return **401 without session cookies** — so the app cannot fetch them
    /// directly. Those get rewritten through the proxy, which has the cookies.
    ///
    /// Everything else comes from the public `g.espncdn.com` CDN and needs no
    /// help. (Those are SVGs, which SwiftUI cannot render — the UI falls back
    /// to initials for them.)
    static func logoURL(
        for team: ESPNLeagueResponse.TeamDTO,
        imageProxyBase: URL?
    ) -> URL? {
        guard let raw = team.logo, let url = URL(string: raw) else { return nil }

        // ESPN's stock logo art is SVG, which UIImage cannot decode. Reporting
        // no logo lets the UI show its own placeholder immediately, instead of
        // firing a request per team on every launch that can only ever fail.
        // A manager who uploads their own image gets a raster URL on a
        // different host, which is the case handled below.
        if url.pathExtension.lowercased() == "svg" { return nil }

        guard let host = url.host(), host.contains("mystique") else { return url }
        guard let base = imageProxyBase else {
            // Without a proxy this would 401, so report no logo rather than
            // leaving the UI to fail a fetch it can never satisfy.
            return nil
        }
        return base.appending(path: url.path())
    }

    /// ESPN moved from `location` + `nickname` to a single `name` field around
    /// 2023. Support both so older seasons still render.
    private static func displayName(for team: ESPNLeagueResponse.TeamDTO) -> String {
        if let name = team.name, !name.isEmpty { return name }
        let combined = [team.location, team.nickname]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return combined.isEmpty ? "Team \(team.id)" : combined
    }

    private static func ownerIDs(for team: ESPNLeagueResponse.TeamDTO) -> [String] {
        if let owners = team.owners, !owners.isEmpty { return owners }
        return team.primaryOwner.map { [$0] } ?? []
    }

    private static func record(
        from overall: ESPNLeagueResponse.TeamDTO.RecordDTO.Overall?
    ) -> TeamRecord {
        guard let overall else { return .empty }
        return TeamRecord(
            wins: overall.wins ?? 0,
            losses: overall.losses ?? 0,
            ties: overall.ties ?? 0,
            pointsFor: overall.pointsFor ?? 0,
            pointsAgainst: overall.pointsAgainst ?? 0
        )
    }

    static func matchups(from dto: ESPNLeagueResponse, week: Int) -> [Matchup] {
        let items = (dto.schedule ?? []).filter { $0.matchupPeriodId == week }
        return items.enumerated().compactMap { index, item in
            guard let home = item.home else { return nil }
            let decided = item.winner.map { $0 != "UNDECIDED" } ?? false
            return Matchup(
                id: item.id ?? (week * 1_000 + index),
                week: week,
                home: side(from: home, isComplete: decided),
                away: item.away.map { side(from: $0, isComplete: decided) },
                isComplete: decided
            )
        }
    }

    private static func side(
        from dto: ESPNLeagueResponse.ScheduleItemDTO.SideDTO,
        isComplete: Bool
    ) -> MatchupSide {
        MatchupSide(
            teamID: dto.teamId,
            // While a week is being played ESPN keeps totalPoints at 0.0 and
            // puts the running score in totalPointsLive. Reading only the
            // former meant the scoreboard sat on dashes all Sunday and then
            // filled in after everything had finished — the one time nobody
            // needed it. Once the period is settled totalPoints is the
            // authority, because totalPointsLive stops being updated.
            points: isComplete
                ? (dto.totalPoints ?? 0)
                : (dto.totalPointsLive ?? dto.totalPoints ?? 0),
            // Projections are meaningless once the games are final.
            projectedPoints: isComplete ? nil : dto.totalProjectedPointsLive,
            // A settled week wants the roster that actually played it;
            // ESPN's "current" roster would show whoever is on the team
            // today. A week still going wants the opposite: the matchup-period
            // roster fills in only as players lock, so mid-Sunday it is a
            // handful of names rather than a lineup.
            roster: roster(
                from: isComplete
                    ? (dto.rosterForMatchupPeriod ?? dto.rosterForCurrentScoringPeriod)
                    : (dto.rosterForCurrentScoringPeriod ?? dto.rosterForMatchupPeriod)
            )
        )
    }

    /// What a player is, by ESPN's `defaultPositionId`.
    private static let positions: [Int: String] = [
        1: "QB", 2: "RB", 3: "WR", 4: "TE", 5: "K",
        9: "DT", 10: "DE", 11: "LB", 12: "CB", 13: "S", 14: "DB",
        16: "D/ST", 17: "P", 18: "HC",
    ]

    /// Where a player is being played, by ESPN's `lineupSlotId`, with the
    /// order a lineup is conventionally read in.
    ///
    /// The bench and injured reserve sort last on purpose: a boxscore is read
    /// starters first, and burying the people who actually scored underneath
    /// the ones who did not would be a strange way to show it.
    private static let slots: [Int: (label: String, rank: Int, isStarter: Bool)] = [
        0: ("QB", 0, true),
        2: ("RB", 1, true),
        4: ("WR", 2, true),
        6: ("TE", 3, true),
        23: ("FLEX", 4, true),
        3: ("RB/WR", 4, true),
        5: ("WR/TE", 4, true),
        7: ("OP", 5, true),
        16: ("D/ST", 6, true),
        17: ("K", 7, true),
        8: ("DT", 8, true), 9: ("DE", 8, true), 10: ("LB", 8, true),
        11: ("DL", 8, true), 12: ("CB", 8, true), 13: ("S", 8, true),
        14: ("DB", 8, true), 15: ("DP", 8, true), 18: ("P", 8, true),
        19: ("HC", 8, true),
        20: ("Bench", 98, false),
        21: ("IR", 99, false),
    ]

    private static func roster(
        from dto: ESPNLeagueResponse.ScheduleItemDTO.SideDTO.RosterDTO?
    ) -> [RosterEntry] {
        guard let entries = dto?.entries else { return [] }

        return entries.compactMap { entry -> (RosterEntry, Int)? in
            guard let pool = entry.playerPoolEntry else { return nil }
            let player = pool.player
            // A player with no id cannot be identified or deduplicated, and a
            // row with no name is not worth showing anybody.
            guard let id = player?.id ?? pool.id, let name = player?.fullName else {
                return nil
            }
            // An unknown slot is treated as a starter: ESPN adds slots for new
            // formats, and hiding somebody who is scoring is worse than
            // showing a slot label we do not have a name for.
            let slot = slots[entry.lineupSlotId ?? -1] ?? ("—", 50, true)
            return (
                RosterEntry(
                    playerID: id,
                    name: name,
                    position: positions[player?.defaultPositionId ?? -1] ?? "—",
                    slot: slot.label,
                    isStarter: slot.isStarter,
                    points: pool.appliedStatTotal ?? 0
                ),
                slot.rank
            )
        }
        // Stable within a slot: ESPN's own roster order, which is how the two
        // running backs stay in the same order between refreshes.
        .enumerated()
        .sorted { left, right in
            left.element.1 == right.element.1
                ? left.offset < right.offset
                : left.element.1 < right.element.1
        }
        .map(\.element.0)
    }
}
