import OSLog
import SwiftUI

/// Stable identity for each tab, so selection can be driven programmatically.
enum TabIdentifier: String, Hashable, CaseIterable {
    case news, matchups, polls, members, settings

    /// Which tab to open on launch.
    ///
    /// In debug builds, `-initialTab matchups` overrides it, so screenshots and
    /// UI tests can open a specific tab without simulating taps. Release builds
    /// always start on News.
    ///
    /// Reads argv rather than UserDefaults. The argument domain is only
    /// consulted on a genuine cold start, so after the scene has been restored
    /// the value silently stops arriving — the same class of problem that made
    /// the credential seeder drop the SWID.
    static var initial: TabIdentifier {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-initialTab"),
           arguments.index(after: index) < arguments.endIndex,
           let tab = TabIdentifier(rawValue: arguments[arguments.index(after: index)]) {
            Logger(subsystem: "com.commissionerscartel.app", category: "launch")
                .notice("Opening on tab \(tab.rawValue) from launch arguments")
            return tab
        }
        #endif
        return .news
    }
}

struct RootView: View {
    @State private var selection: TabIdentifier = .initial

    var body: some View {
        TabView(selection: $selection) {
            Tab("News", systemImage: "newspaper", value: TabIdentifier.news) {
                NewsFeedView()
            }
            Tab("Matchups", systemImage: "sportscourt", value: TabIdentifier.matchups) {
                MatchupsView()
            }
            Tab("Polls", systemImage: "chart.bar", value: TabIdentifier.polls) {
                PollsView()
            }
            Tab("Members", systemImage: "person.3", value: TabIdentifier.members) {
                MembersView()
            }
            Tab("Settings", systemImage: "gearshape", value: TabIdentifier.settings) {
                SettingsView()
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment.preview)
}
