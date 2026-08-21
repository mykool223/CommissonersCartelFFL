import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("News", systemImage: "newspaper") {
                NewsFeedView()
            }
            Tab("Matchups", systemImage: "sportscourt") {
                MatchupsView()
            }
            Tab("Polls", systemImage: "chart.bar") {
                PollsView()
            }
            Tab("Members", systemImage: "person.3") {
                MembersView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment.preview)
}
