import Foundation

/// Read-only league data. Backed by ESPN in production and by
/// `MockLeagueDataSource` in previews and tests.
///
/// Every screen depends on this protocol rather than on `CartelESPN` directly,
/// so the ESPN scraping layer can be replaced without touching the UI.
public protocol LeagueDataSource: Sendable {
    func league() async throws -> League
    func managers() async throws -> [Manager]
    func teams() async throws -> [Team]
    func matchups(week: Int) async throws -> [Matchup]

    /// Drops any cached payload so the next read goes to the network.
    ///
    /// Wired to pull-to-refresh. Without it the ESPN client would serve its
    /// cached response for the whole TTL, so pulling to refresh right after a
    /// manager changed their team name or uploaded a logo would show the old
    /// data and look broken.
    func refresh() async
}

public extension LeagueDataSource {
    /// Nothing cached by default.
    func refresh() async {}
}

/// League-authored content. Backed by Supabase in production.
public protocol ContentRepository: Sendable {
    func newsPosts(season: Int, limit: Int) async throws -> [NewsPost]
    func recaps(season: Int, week: Int) async throws -> [Recap]
    func polls(season: Int) async throws -> [Poll]

    /// Player news blurbs collected by the daily ingest job.
    func playerNews(limit: Int) async throws -> [PlayerNews]

    /// The signed-in member's own conversation with the coach, oldest first.
    /// Their own only: row level security sees to that, and so does the coach.
    func coachHistory(limit: Int) async throws -> [CoachMessage]

    /// The league's power ranking, best first. Empty until one is published.
    func powerRankings(season: Int) async throws -> [PowerRanking]

    /// The league's trophy case, newest first.
    func trophies(season: Int) async throws -> [Trophy]

    /// Adds, drops, waivers and trades. Readable signed out, like league news.
    func leagueActivity(season: Int, limit: Int) async throws -> [LeagueActivity]

    /// Flavour text for each team, keyed by ESPN team id. Readable signed
    /// out, so the members list can show it before anyone logs in.
    func teamBios(season: Int) async throws -> [Int: TeamBio]

    /// Records the caller's vote. Replaces any previous vote on the same poll.
    func vote(pollID: UUID, optionID: UUID) async throws
}

public extension ContentRepository {
    func newsPosts(season: Int) async throws -> [NewsPost] {
        try await newsPosts(season: season, limit: 50)
    }

    func playerNews() async throws -> [PlayerNews] {
        try await playerNews(limit: 40)
    }

    func leagueActivity(season: Int) async throws -> [LeagueActivity] {
        try await leagueActivity(season: season, limit: 100)
    }
}

/// Errors surfaced to the UI. Anything lower-level gets wrapped in `.transport`
/// or `.decoding` so views only ever switch over these cases.
public enum CartelError: Error, Sendable {
    /// The league is private and the request had no valid ESPN credentials.
    case notAuthorized
    /// ESPN or Supabase returned a non-2xx status.
    case server(statusCode: Int, message: String?)
    /// The response parsed but did not contain what we expected. Usually means
    /// ESPN changed their payload shape.
    case decoding(String)
    /// URLSession failed: offline, DNS, TLS, timeout.
    case transport(String)
    /// Configuration is missing or malformed, e.g. no league id set.
    case notConfigured(String)
}

extension CartelError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "This league is private. Add your ESPN credentials in Settings."
        case let .server(statusCode, message):
            return message ?? "The server returned an error (\(statusCode))."
        case let .decoding(detail):
            return "Couldn't read the response. \(detail)"
        case let .transport(detail):
            return "Network problem. \(detail)"
        case let .notConfigured(detail):
            return "Not set up yet. \(detail)"
        }
    }
}

/// Push notification registration and per-member preferences.
///
/// Sending happens server-side: a database trigger fires when a message, news
/// post, or poll is inserted, so notifications do not depend on any client
/// being awake. The app's only jobs are handing over its device token and
/// remembering which kinds the member wants.
public protocol PushRepository: Sendable {
    /// Stores this device's APNs token against the signed-in user. Safe to
    /// call on every launch: the token is the primary key, so a repeat is an
    /// update rather than a duplicate.
    func registerDevice(token: String, environment: PushEnvironment) async throws

    /// Removes this device. Called when a member turns notifications off, so
    /// the server stops sending rather than sending into the void.
    func unregisterDevice(token: String) async throws

    func notificationPreferences() async throws -> NotificationPreferences
    func setNotificationPreferences(_ preferences: NotificationPreferences) async throws
}

/// Which APNs host a token belongs to. A token minted under one is rejected by
/// the other, so it travels with the token rather than being assumed.
public enum PushEnvironment: String, Sendable {
    /// Xcode builds run against Apple's sandbox.
    case sandbox
    /// TestFlight and App Store builds.
    case production

    /// Debug builds are sandbox; anything archived is production.
    public static var current: PushEnvironment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }
}

/// What a member wants to hear about. Everything on by default: a member who
/// never opens Settings should still be told when the league is talking.
public struct NotificationPreferences: Equatable, Sendable {
    public var messages: Bool
    public var news: Bool
    public var polls: Bool
    /// Adds, drops and trades. Separately mutable because roster churn is
    /// noisier than the rest and some people will not want it.
    public var activity: Bool
    /// Sunday warnings about a starter who cannot play.
    public var lineup: Bool
    /// Lead changes and final scores in your own fixture.
    public var matchups: Bool
    /// Private messages from another member.
    public var direct: Bool
    /// Somebody typing your name in the league thread.
    public var mentions: Bool
    /// News about a player on your own roster, as it lands.
    public var rosterNews: Bool

    public static let all = NotificationPreferences()

    /// Everything off. Defined next to the properties so adding a kind and
    /// forgetting this is one edit away rather than one file away — and there
    /// is a test that catches it if you do.
    public static let none = NotificationPreferences(
        messages: false, news: false, polls: false,
        activity: false, lineup: false, matchups: false,
        direct: false, mentions: false, rosterNews: false
    )

    public init(
        messages: Bool = true,
        news: Bool = true,
        polls: Bool = true,
        activity: Bool = true,
        lineup: Bool = true,
        matchups: Bool = true,
        direct: Bool = true,
        mentions: Bool = true,
        rosterNews: Bool = true
    ) {
        self.messages = messages
        self.news = news
        self.polls = polls
        self.activity = activity
        self.lineup = lineup
        self.matchups = matchups
        self.direct = direct
        self.mentions = mentions
        self.rosterNews = rosterNews
    }

    public var isAnythingEnabled: Bool {
        messages || news || polls || activity || lineup || matchups
            || direct || mentions || rosterNews
    }
}
