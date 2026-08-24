import Foundation
import CartelCore
import CartelESPN

/// The widget's own copy of the ESPN configuration.
///
/// It cannot ask the app: a widget is a separate process. The same Info.plist
/// keys are set on this target, so the values arrive the same way.
struct WidgetConfigurationValues {
    private func string(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    var espnClient: ESPNClient? {
        guard
            let leagueID = string("ESPNLeagueID"),
            let host = string("SupabaseHost"),
            let anonKey = string("SupabaseAnonKey"),
            let url = URL(string: "https://\(host)")
        else { return nil }

        return ESPNClient(
            configuration: .viaProxy(
                leagueID: leagueID,
                season: Season.current(),
                supabaseURL: url,
                accessToken: anonKey
            )
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
