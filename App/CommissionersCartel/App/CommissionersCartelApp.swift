import SwiftUI

@main
struct CommissionersCartelApp: App {
    /// Built once from Info.plist. With no league id or Supabase project
    /// configured this wires up mock data, so a fresh clone runs immediately.
    @State private var environment = CommissionersCartelApp.makeEnvironment()

    /// Kept as a factory so debug credential seeding happens *before* the
    /// environment is constructed — AppEnvironment reads the Keychain when it
    /// builds the ESPN client, so seeding afterwards would be a launch too late.
    #if DEBUG
    /// Reads `-name value` out of argv. Not UserDefaults: it parses values that
    /// look like property lists, and a URL with a fragment is close enough to
    /// trip it.
    static func launchArgument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-\(name)"),
              arguments.index(after: index) < arguments.endIndex
        else { return nil }
        let value = arguments[arguments.index(after: index)]
        return value.isEmpty ? nil : value
    }
    #endif

    private static func makeEnvironment() -> AppEnvironment {
        #if DEBUG
        KeychainStore.seedFromLaunchArgumentsIfNeeded()
        #endif
        return AppEnvironment(configuration: .fromBundle())
    }

    var body: some Scene {
        WindowGroup {
            RootContainerView()
                .environment(environment)
                .task {
                    await environment.restoreSession()
                    #if DEBUG
                    // `-authCallback <url>` completes sign-in without tapping
                    // through the system's "Open in Cartel?" prompt, which
                    // cannot be automated. Debug builds only.
                    if let raw = CommissionersCartelApp.launchArgument("authCallback"),
                       let url = URL(string: raw) {
                        try? await environment.handleAuthCallback(url: url)
                    }
                    #endif
                }
                .onOpenURL { url in
                    // The emailed magic link lands here.
                    Task { try? await environment.handleAuthCallback(url: url) }
                }
        }
    }
}

/// Holds the splash over the app until the first content has had a moment to
/// load, then cross-fades.
///
/// The delay is a floor, not a fixed wait: the tabs are already loading
/// underneath, so by the time this clears the News feed usually has content
/// rather than a spinner.
private struct RootContainerView: View {
    /// Long enough to register as deliberate, short enough not to be in the way.
    private static let minimumDisplay = Duration.milliseconds(1_400)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowingSplash = true

    var body: some View {
        ZStack {
            RootView()

            if isShowingSplash {
                SplashView()
                    // Only the splash fades; the app underneath is already
                    // laid out, so there is nothing to animate in.
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(for: Self.minimumDisplay)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
                isShowingSplash = false
            }
        }
    }
}
