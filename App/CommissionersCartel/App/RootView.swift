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

/// What the unread count depends on. Either changing is a reason to recount.
private struct TabRefreshKey: Equatable {
    let tab: TabIdentifier
    let user: UUID?
}

extension Notification.Name {
    /// Posted when messages are sent or read, so the tab mark can catch up
    /// without polling.
    static let directMessagesChanged = Notification.Name("directMessagesChanged")
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(PushRegistrar.self) private var registrar

    @State private var selection: TabIdentifier = .initial
    @State private var unreadDirect = 0

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
            // Private messages live under Members, so that is where somebody
            // looks after a notification — and where the mark has to be for
            // anyone who never saw the notification at all.
            .badge(unreadDirect)
            Tab("Settings", systemImage: "gearshape", value: TabIdentifier.settings) {
                SettingsView()
            }
        }
        // Keyed on the session as well as the tab: the first run happens
        // before sign-in has settled, and a tab that is already selected never
        // changes, so keying on the tab alone means it never runs again.
        .task(id: TabRefreshKey(tab: selection, user: environment.session?.userID)) {
            await refreshUnread()
        }
        // A message can arrive while the app is open and on another tab.
        .onReceive(
            NotificationCenter.default.publisher(for: .directMessagesChanged)
        ) { _ in
            Task { await refreshUnread() }
        }
        // A tapped notification names the tab it came from.
        //
        // Both hooks are needed. A tap on a *running* app changes the value
        // while this view is on screen, which onChange sees. A tap that
        // launches the app sets it before this view exists — onChange never
        // fires for a value that was already there, so the app opens on News
        // as though the notification had not been tapped at all.
        .onAppear { openPendingDestination() }
        .onChange(of: registrar.pendingDestination) { _, _ in
            openPendingDestination()
        }
        // Asked the first time someone signs in rather than at first launch:
        // the prompt makes sense once you know there are eleven other people
        // who might post, and it can only ever be shown once.
        .task(id: environment.session?.userID) {
            guard environment.isSignedIn, environment.push != nil else { return }
            await registrar.refreshAuthorizationStatus()
            if registrar.authorization == .notDetermined {
                await registrar.requestAuthorization()
            }
        }
    }

    /// Follows a tapped notification to the tab it names, if one is waiting.
    private func openPendingDestination() {
        guard let destination = registrar.pendingDestination,
              let tab = TabIdentifier(rawValue: destination)
        else { return }
        selection = tab
        registrar.clearPendingDestination()
    }

    /// Counts what is waiting. Quietly: a failure here should cost a badge,
    /// never a working tab bar.
    private func refreshUnread() async {
        guard environment.isSignedIn, let chat = environment.chat else {
            unreadDirect = 0
            return
        }
        guard let messages = try? await chat.directMessages() else { return }
        let me = environment.session?.userID
        unreadDirect = messages.count { $0.isUnread(for: me) }
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment.preview)
        .environment(PushRegistrar())
}
