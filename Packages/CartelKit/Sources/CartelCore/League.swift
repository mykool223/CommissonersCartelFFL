import Foundation

/// Identifies one ESPN fantasy league in one season. ESPN scopes almost every
/// endpoint by both values, so they travel together.
public struct LeagueRef: Hashable, Sendable, Codable {
    public let leagueID: String
    public let season: Int

    public init(leagueID: String, season: Int) {
        self.leagueID = leagueID
        self.season = season
    }
}

/// League-level metadata, mostly for headers and the settings screen.
public struct League: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let season: Int
    public let currentWeek: Int
    public let regularSeasonWeeks: Int
    public let teamCount: Int

    public init(
        id: String,
        name: String,
        season: Int,
        currentWeek: Int,
        regularSeasonWeeks: Int,
        teamCount: Int
    ) {
        self.id = id
        self.name = name
        self.season = season
        self.currentWeek = currentWeek
        self.regularSeasonWeeks = regularSeasonWeeks
        self.teamCount = teamCount
    }

    public var isPlayoffs: Bool { currentWeek > regularSeasonWeeks }
}
