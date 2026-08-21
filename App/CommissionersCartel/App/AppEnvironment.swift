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
        content: (any ContentRepository)? = nil
    ) {
        self.configuration = configuration

        if let leagueData {
            self.leagueData = leagueData
            self.isUsingMockLeagueData = false
        } else if configuration.hasESPN {
            self.leagueData = AppEnvironment.makeESPNClient(configuration)
            self.isUsingMockLeagueData = false
        } else {
            self.leagueData = MockLeagueDataSource()
            self.isUsingMockLeagueData = true
        }

        if let content {
            self.content = content
            self.isUsingMockContent = false
        } else if let url = configuration.supabaseURL, configuration.hasSupabase {
            self.content = SupabaseContentRepository(
                client: SupabaseClient(
                    configuration: SupabaseConfiguration(
                        url: url, anonKey: configuration.supabaseAnonKey
                    )
                )
            )
            self.isUsingMockContent = false
        } else {
            self.content = MockContentRepository()
            self.isUsingMockContent = true
        }
    }

    /// Rebuilds the ESPN client after credentials change in Settings, so a
    /// private league starts working without relaunching the app.
    func reloadESPNCredentials() {
        guard configuration.hasESPN else { return }
        leagueData = AppEnvironment.makeESPNClient(configuration)
        isUsingMockLeagueData = false
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
            content: MockContentRepository(latency: .zero)
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
            content: MockContentRepository(latency: .zero, failure: error)
        )
    }
}
