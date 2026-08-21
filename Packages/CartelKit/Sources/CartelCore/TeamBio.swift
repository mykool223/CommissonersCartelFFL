import Foundation

/// A line of flavour attached to a team.
///
/// Keyed by ESPN's team id rather than a name, because managers rename teams
/// mid-season and the bio should follow the seat rather than the sign on it.
public struct TeamBio: Identifiable, Hashable, Sendable {
    public let season: Int
    public let teamID: Int
    /// The role, as in "The Boss".
    public let title: String
    public let bio: String

    public var id: Int { teamID }

    public init(season: Int, teamID: Int, title: String, bio: String) {
        self.season = season
        self.teamID = teamID
        self.title = title
        self.bio = bio
    }
}
