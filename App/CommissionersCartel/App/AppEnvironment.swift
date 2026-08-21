import Foundation
import Observation
import CartelCore
import CartelESPN
import CartelSupabase

/// The app's dependency container, handed down through the SwiftUI environment.
///
/// Views never construct a client themselves; they read `leagueData` and
/// `content` off this object. That's what lets every screen run against mock
/// data with no backend configured, and lets previews inject failures.
@Observable
@MainActor
final class AppEnvironment {
    let configuration: AppConfiguration
    private(set) var leagueData: any LeagueDataSource
    private(set) var content: any ContentRepository
    /// Public NFL scores. Needs no configuration, so it is always live — even
    /// when the league itself is running on sample data.
    let nflScoreboard: any NFLScoreboardSource

    /// Nil when Supabase is not configured, in which case the app runs
    /// signed-out on sample content.
    let auth: SupabaseAuth?
    /// The signed-in member, or nil. Observed by the UI.
    private(set) var session: AuthSession?
    /// True once the stored session has been checked, so the UI does not flash
    /// a sign-in screen at someone who is already signed in.
    private(set) var hasCheckedSession = false

    /// True when either backend is running on sample data, so the UI can say so
    /// rather than quietly showing fake standings as if they were real.
    private(set) var isUsingMockLeagueData: Bool
    private(set) var isUsingMockContent: Bool

    var season: Int { configuration.season }

    /// Headers required to fetch team logos through the proxy. Empty when
    /// talking to ESPN directly, where uploaded logos are unreachable anyway.
    var espnImageHeaders: [String: String] {
        guard configuration.usesESPNProxy, !configuration.supabaseAnonKey.isEmpty else {
            return [:]
        }
        return [
            "Authorization": "Bearer \(configuration.supabaseAnonKey)",
            "apikey": configuration.supabaseAnonKey,
        ]
    }

    init(
        configuration: AppConfiguration,
        leagueData: (any LeagueDataSource)? = nil,
        content: (any ContentRepository)? = nil,
        nflScoreboard: (any NFLScoreboardSource)? = nil
    ) {
        self.configuration = configuration
        self.nflScoreboard = nflScoreboard
            ?? (AppEnvironment.isForcedToMockData
                ? MockNFLScoreboardSource()
                : ESPNScoreboardClient())

        let forceMock = AppEnvironment.isForcedToMockData

        if let leagueData {
            self.leagueData = leagueData
            self.isUsingMockLeagueData = false
        } else if configuration.hasESPN, !forceMock {
            self.leagueData = AppEnvironment.makeESPNClient(configuration)
            self.isUsingMockLeagueData = false
        } else {
            self.leagueData = MockLeagueDataSource()
            self.isUsingMockLeagueData = true
        }

        if let content {
            self.auth = nil
            self.content = content
            self.isUsingMockContent = false
        } else if let url = configuration.supabaseURL, configuration.hasSupabase, !forceMock {
            let supabase = SupabaseConfiguration(url: url, anonKey: configuration.supabaseAnonKey)
            let auth = SupabaseAuth(configuration: supabase, store: KeychainSessionStore())
            self.auth = auth
            self.content = SupabaseContentRepository(
                client: SupabaseClient(
                    configuration: supabase,
                    // Read per request rather than captured once, so a token
                    // refreshed mid-session is picked up without rebuilding
                    // anything.
                    accessToken: { await auth.accessToken() }
                )
            )
            self.isUsingMockContent = false
        } else {
            self.auth = nil
            self.content = MockContentRepository()
            self.isUsingMockContent = true
        }
    }

    // MARK: - Sign-in

    /// Restores a stored session at launch.
    func restoreSession() async {
        session = await auth?.currentSession()
        hasCheckedSession = true
    }

    /// Emails a sign-in link.
    func sendMagicLink(to email: String) async throws {
        guard let auth else {
            throw CartelError.notConfigured("Supabase isn't set up in this build.")
        }
        try await auth.sendMagicLink(to: email)
    }

    /// Completes sign-in from the URL the emailed link opens.
    func handleAuthCallback(url: URL) async throws {
        guard let auth else { return }
        session = try await auth.handleCallback(url: url)
    }

    func signOut() async {
        await auth?.signOut()
        session = nil
    }

    var isSignedIn: Bool { session != nil }

    /// The league thread, when Supabase is configured. Nil on sample data,
    /// where there is nobody to talk to.
    var chat: (any LeagueChatRepository)? {
        content as? any LeagueChatRepository
    }

    /// Rebuilds the ESPN client after credentials change in Settings, so a
    /// private league starts working without relaunching the app.
    func reloadESPNCredentials() {
        guard configuration.hasESPN else { return }
        leagueData = AppEnvironment.makeESPNClient(configuration)
        isUsingMockLeagueData = false
    }

    /// Debug builds honour `-useMockData 1`, which forces every screen onto
    /// sample data regardless of configuration.
    ///
    /// Useful for screenshots and for exercising screens the real league cannot
    /// populate yet — a recap has nothing to show until games have been played.
    static var isForcedToMockData: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-useMockData"),
              arguments.index(after: index) < arguments.endIndex
        else { return false }
        return arguments[arguments.index(after: index)] == "1"
        #else
        return false
        #endif
    }

    private static func makeESPNClient(_ configuration: AppConfiguration) -> ESPNClient {
        // Preferred path: the edge function holds the ESPN cookies as a
        // server-side secret, so nothing sensitive ships in the app binary and
        // an expired cookie is fixed once for the whole league rather than by
        // twelve people each digging through developer tools.
        if configuration.usesESPNProxy, let supabaseURL = configuration.supabaseURL {
            return ESPNClient(
                configuration: .viaProxy(
                    leagueID: configuration.espnLeagueID,
                    season: configuration.season,
                    supabaseURL: supabaseURL,
                    // The anon key until sign-in exists; swap in the user's
                    // access token then, and flip ESPN_PROXY_REQUIRE_AUTH on
                    // the function to lock anon out.
                    accessToken: configuration.supabaseAnonKey
                )
            )
        }

        // Fallback: talk to ESPN directly with credentials from the Keychain.
        let stored = KeychainStore.espnCredentials
        return ESPNClient(
            configuration: ESPNConfiguration(
                leagueID: configuration.espnLeagueID,
                season: configuration.season,
                credentials: stored.map {
                    ESPNCredentials(espnS2: $0.espnS2, swid: $0.swid)
                }
            )
        )
    }

    // MARK: - Previews

    /// Fast, deterministic environment for SwiftUI previews. No latency, so
    /// previews render content immediately instead of a spinner.
    static var preview: AppEnvironment {
        AppEnvironment(
            configuration: AppConfiguration(
                espnLeagueID: "", season: MockData.season,
                supabaseURL: nil, supabaseAnonKey: "", usesESPNProxy: false
            ),
            leagueData: MockLeagueDataSource(latency: .zero),
            content: MockContentRepository(latency: .zero),
            nflScoreboard: MockNFLScoreboardSource(latency: .zero)
        )
    }

    /// Every screen in its error state, for checking that failures look right.
    static func previewFailing(_ error: CartelError = .notAuthorized) -> AppEnvironment {
        AppEnvironment(
            configuration: AppConfiguration(
                espnLeagueID: "", season: MockData.season,
                supabaseURL: nil, supabaseAnonKey: "", usesESPNProxy: false
            ),
            leagueData: MockLeagueDataSource(latency: .zero, failure: error),
            content: MockContentRepository(latency: .zero, failure: error),
            nflScoreboard: MockNFLScoreboardSource(latency: .zero, failure: error)
        )
    }
}
