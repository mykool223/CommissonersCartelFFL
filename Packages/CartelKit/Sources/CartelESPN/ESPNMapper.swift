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
            points: dto.totalPoints ?? 0,
            // Projections are meaningless once the games are final.
            projectedPoints: isComplete ? nil : dto.totalProjectedPointsLive
        )
    }
}
