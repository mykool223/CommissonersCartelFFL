import Foundation

/// Supplies a logo for teams that never uploaded one to ESPN.
///
/// Eight of the twelve are still on ESPN's stock art. That art is SVG, which
/// the app cannot decode, so those teams already arrive with no logo at all —
/// and the members list becomes a wall of identical crests, which is the one
/// thing a logo exists to prevent.
///
/// This wraps the ESPN source rather than changing every screen that draws a
/// logo: standings, matchups, the recap and the claim sheet all read the same
/// `Team.logoURL`, so patching it once means none of them need to know.
///
/// A team that has its own ESPN logo keeps it. If somebody uploads one later,
/// theirs wins the moment ESPN serves it — we never overwrite a real choice.
public actor LeagueLogos: LeagueDataSource {
    private let upstream: any LeagueDataSource
    private let content: any ContentRepository
    private let season: Int

    private var overrides: [Int: URL]?

    public init(wrapping upstream: any LeagueDataSource,
                content: any ContentRepository,
                season: Int) {
        self.upstream = upstream
        self.content = content
        self.season = season
    }

    public func league() async throws -> League { try await upstream.league() }
    public func managers() async throws -> [Manager] { try await upstream.managers() }
    public func matchups(week: Int) async throws -> [Matchup] {
        try await upstream.matchups(week: week)
    }

    public func teams() async throws -> [Team] {
        let teams = try await upstream.teams()
        let byTeam = await logoOverrides()
        guard !byTeam.isEmpty else { return teams }
        return teams.map { team in
            // Only fills a gap. A team with its own logo is left alone.
            guard team.logoURL == nil, let url = byTeam[team.id] else { return team }
            return team.withLogo(url)
        }
    }

    public func refresh() async {
        overrides = nil
        await upstream.refresh()
    }

    /// Read once per launch. Losing them costs a picture, not a screen, so a
    /// failure is remembered as "none" rather than retried on every read.
    private func logoOverrides() async -> [Int: URL] {
        if let overrides { return overrides }
        let bios = (try? await content.teamBios(season: season)) ?? [:]
        let resolved = bios.compactMapValues { bio -> URL? in
            bio.logoURL.flatMap(URL.init(string:))
        }
        overrides = resolved
        return resolved
    }
}
