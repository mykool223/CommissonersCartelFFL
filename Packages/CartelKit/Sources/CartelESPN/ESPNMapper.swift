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
        return League(
            id: String(dto.id),
            name: dto.settings?.name ?? "Fantasy League",
            season: dto.seasonId ?? fallbackSeason,
            currentWeek: max(1, current),
            regularSeasonWeeks: regularSeasonWeeks,
            teamCount: dto.teams?.count ?? 0
        )
    }

    static func managers(from dto: ESPNLeagueResponse) -> [Manager] {
        (dto.members ?? []).map { member in
            Manager(
                id: member.id,
                displayName: member.displayName ?? member.id,
                firstName: member.firstName,
                lastName: member.lastName,
                isCommissioner: member.isLeagueManager ?? false
            )
        }
    }

    static func teams(from dto: ESPNLeagueResponse) -> [Team] {
        (dto.teams ?? []).map { team in
            Team(
                id: team.id,
                name: displayName(for: team),
                abbreviation: team.abbrev ?? "T\(team.id)",
                logoURL: team.logo.flatMap(URL.init(string:)),
                ownerIDs: ownerIDs(for: team),
                record: record(from: team.record?.overall),
                playoffSeed: team.playoffSeed
            )
        }
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
