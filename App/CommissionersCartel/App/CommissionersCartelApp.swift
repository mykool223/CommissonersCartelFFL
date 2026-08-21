import SwiftUI

@main
struct CommissionersCartelApp: App {
    /// Built once from Info.plist. With no league id or Supabase project
    /// configured this wires up mock data, so a fresh clone runs immediately.
    @State private var environment = CommissionersCartelApp.makeEnvironment()

    /// Kept as a factory so debug credential seeding happens *before* the
    /// environment is constructed — AppEnvironment reads the Keychain when it
    /// builds the ESPN client, so seeding afterwards would be a launch too late.
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
