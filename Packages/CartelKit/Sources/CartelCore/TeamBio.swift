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
    /// A logo the league supplied, for a team still on ESPN's stock art.
    public let logoURL: String?

    public var id: Int { teamID }

    public init(
        season: Int, teamID: Int, title: String, bio: String,
        logoURL: String? = nil
    ) {
        self.season = season
        self.teamID = teamID
        self.title = title
        self.logoURL = logoURL
        self.bio = bio
    }
}
