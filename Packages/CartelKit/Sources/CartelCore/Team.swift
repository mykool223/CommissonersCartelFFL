import Foundation

/// A fantasy roster slot in the league, owned by one or more `Manager`s.
public struct Team: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public let name: String
    public let abbreviation: String
    public let logoURL: URL?
    /// SWIDs of the owning managers. Co-owned teams have more than one.
    public let ownerIDs: [String]
    public let record: TeamRecord
    /// Standings position as ESPN computes it. Nil before the season starts.
    public let playoffSeed: Int?
    /// Which division the team belongs to. Nil in leagues without divisions.
    public let divisionID: Int?

    public init(
        id: Int,
        name: String,
        abbreviation: String,
        logoURL: URL? = nil,
        ownerIDs: [String] = [],
        record: TeamRecord = .empty,
        playoffSeed: Int? = nil,
        divisionID: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.logoURL = logoURL
        self.ownerIDs = ownerIDs
        self.record = record
        self.playoffSeed = playoffSeed
        self.divisionID = divisionID
    }

    /// The same team with a different logo. Used when the league supplies one
    /// for a manager who never uploaded their own.
    public func withLogo(_ url: URL?) -> Team {
        Team(
            id: id, name: name, abbreviation: abbreviation, logoURL: url,
            ownerIDs: ownerIDs, record: record, playoffSeed: playoffSeed,
            divisionID: divisionID
        )
    }
}

public struct TeamRecord: Hashable, Sendable, Codable {
    public let wins: Int
    public let losses: Int
    public let ties: Int
    public let pointsFor: Double
    public let pointsAgainst: Double

    public static let empty = TeamRecord(
        wins: 0, losses: 0, ties: 0, pointsFor: 0, pointsAgainst: 0
    )

    public init(wins: Int, losses: Int, ties: Int, pointsFor: Double, pointsAgainst: Double) {
        self.wins = wins
        self.losses = losses
        self.ties = ties
        self.pointsFor = pointsFor
        self.pointsAgainst = pointsAgainst
    }

    public var gamesPlayed: Int { wins + losses + ties }

    /// Ties count as half a win, matching how ESPN sorts standings.
    public var winPercentage: Double {
        guard gamesPlayed > 0 else { return 0 }
        return (Double(wins) + Double(ties) * 0.5) / Double(gamesPlayed)
    }

    /// "7-5" or "7-5-1" when there are ties.
    public var summary: String {
        ties > 0 ? "\(wins)-\(losses)-\(ties)" : "\(wins)-\(losses)"
    }

    public var pointDifferential: Double { pointsFor - pointsAgainst }
}
