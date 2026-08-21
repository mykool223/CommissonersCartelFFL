import SwiftUI

/// Stable identity for each tab, so selection can be driven programmatically.
enum TabIdentifier: String, Hashable, CaseIterable {
    case news, matchups, polls, members, settings

    /// Which tab to open on launch.
    ///
    /// In debug builds, `-initialTab matchups` overrides it. Foundation turns
    /// `-key value` launch arguments into UserDefaults entries automatically,
    /// so this needs no parsing. It exists so screenshots and UI tests can open
    /// a specific tab instead of simulating taps; release builds always start
    /// on News.
    static var initial: TabIdentifier {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "initialTab"),
           let tab = TabIdentifier(rawValue: raw) {
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
