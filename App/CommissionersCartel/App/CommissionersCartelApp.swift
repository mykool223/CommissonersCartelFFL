import SwiftUI

@main
struct CommissionersCartelApp: App {
    /// Built once from Info.plist. With no league id or Supabase project
    /// configured this wires up mock data, so a fresh clone runs immediately.
    @State private var environment = AppEnvironment(configuration: .fromBundle())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
        }
    }
}
