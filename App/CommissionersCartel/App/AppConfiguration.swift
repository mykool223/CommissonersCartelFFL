import Foundation
import CartelCore
import CartelESPN
import CartelSupabase

/// Build-time settings, injected into Info.plist from `Config/*.xcconfig`.
///
/// Nothing here is secret: the ESPN league id is visible in the league URL and
/// the Supabase anon key is designed to be public (row level security is what
/// protects the data). The one genuinely sensitive value — ESPN session
/// cookies for a private league — is never built in; it lives in the Keychain
/// after the commissioner enters it in Settings.
struct AppConfiguration {
    let espnLeagueID: String
    let season: Int
    let supabaseURL: URL?
    let supabaseAnonKey: String
    /// Route ESPN through the `espn-proxy` edge function rather than talking to
    /// ESPN directly with on-device cookies.
    let usesESPNProxy: Bool

    /// Placeholder text shipped in `Debug.xcconfig`. Treated as "unset" so a
    /// fresh clone runs on mock data instead of firing doomed requests.
    private static let placeholder = "REPLACE_ME"

    static func fromBundle(_ bundle: Bundle = .main) -> AppConfiguration {
        func value(_ key: String) -> String? {
            guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed == placeholder ? nil : trimmed
        }

        return AppConfiguration(
            espnLeagueID: value("ESPNLeagueID") ?? "",
            season: value("LeagueSeason").flatMap(Int.init) ?? AppConfiguration.currentSeason(),
            // xcconfig can't hold "//" (it starts a comment), so the scheme is
            // stored without it and rebuilt here.
            supabaseURL: value("SupabaseHost").flatMap { URL(string: "https://\($0)") },
            supabaseAnonKey: value("SupabaseAnonKey") ?? "",
            usesESPNProxy: (value("ESPNViaProxy") ?? "NO").uppercased() == "YES"
        )
    }

    /// Delegates to `Season.current` so the app and the sample data can never
    /// disagree about which season it is.
    static func currentSeason(now: Date = Date(), calendar: Calendar = .current) -> Int {
        Season.current(now: now, calendar: calendar)
    }

    var hasESPN: Bool { !espnLeagueID.isEmpty }
    var hasSupabase: Bool { supabaseURL != nil && !supabaseAnonKey.isEmpty }
    /// True on a fresh clone, before either backend is configured.
    var isFullyMocked: Bool { !hasESPN && !hasSupabase }
}
