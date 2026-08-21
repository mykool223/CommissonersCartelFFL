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

/// A division within the league. ESPN allows leagues to split into groups that
/// affect scheduling and playoff seeding.
public struct Division: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public let name: String
    public let size: Int

    public init(id: Int, name: String, size: Int) {
        self.id = id
        self.name = name
        self.size = size
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
    /// Empty for a league that isn't split into divisions.
    public let divisions: [Division]

    public init(
        id: String,
        name: String,
        season: Int,
        currentWeek: Int,
        regularSeasonWeeks: Int,
        teamCount: Int,
        divisions: [Division] = []
    ) {
        self.id = id
        self.name = name
        self.season = season
        self.currentWeek = currentWeek
        self.regularSeasonWeeks = regularSeasonWeeks
        self.teamCount = teamCount
        self.divisions = divisions
    }

    public var hasDivisions: Bool { divisions.count > 1 }

    public var isPlayoffs: Bool { currentWeek > regularSeasonWeeks }
}
