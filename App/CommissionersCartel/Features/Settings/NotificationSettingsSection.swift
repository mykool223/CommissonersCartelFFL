import SwiftUI
import UserNotifications
import CartelCore

/// Notification toggles for the Settings form.
///
/// Only shown to a signed-in member: a notification is addressed to a person,
/// and the app does not know who an anonymous reader is.
struct NotificationSettingsSection: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(PushRegistrar.self) private var registrar
    @Environment(\.scenePhase) private var scenePhase

    @State private var preferences = NotificationPreferences.all
    @State private var hasLoaded = false
    @State private var isSaving = false

    var body: some View {
        Section {
            switch registrar.authorization {
            case .notDetermined:
                Button {
                    Task {
                        await registrar.requestAuthorization()
                        await load()
                    }
                } label: {
                    Label("Turn on notifications", systemImage: "bell.badge")
                }

            case .denied:
                // The system prompt only ever appears once, so the only way
                // back is the Settings app.
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open iPhone Settings", systemImage: "arrow.up.forward.app")
                }

            default:
                Toggle("League thread", isOn: binding(\.messages))
                Toggle("League news", isOn: binding(\.news))
                Toggle("New polls", isOn: binding(\.polls))
                Toggle("Adds, drops and trades", isOn: binding(\.activity))
                Toggle("Lineup warnings", isOn: binding(\.lineup))
                Toggle("My matchup", isOn: binding(\.matchups))
                Toggle("Private messages", isOn: binding(\.direct))
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text(footer)
        }
        .disabled(isSaving)
        .task(id: environment.session?.userID) { await load() }
        .onChange(of: scenePhase) { _, phase in
            // Permission can be changed in the Settings app while we are in
            // the background; this screen must not keep showing the old state.
            if phase == .active {
                Task { await registrar.refreshAuthorizationStatus() }
            }
        }
    }

    private var footer: String {
        switch registrar.authorization {
        case .notDetermined:
            "Get a heads-up when someone posts in the league thread, when there's league news, or when a new poll opens."
        case .denied:
            "Notifications are turned off for the Cartel in iPhone Settings. Turn them back on there and these controls will work."
        default:
            preferences.isAnythingEnabled
                ? "You won't be notified about your own posts."
                : "You've turned everything off, so the Cartel will leave you alone."
        }
    }

    private func binding(_ key: WritableKeyPath<NotificationPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { preferences[keyPath: key] },
            set: { newValue in
                var updated = preferences
                updated[keyPath: key] = newValue
                preferences = updated
                Task { await save(updated) }
            }
        )
    }

    private func load() async {
        await registrar.refreshAuthorizationStatus()
        guard let push = environment.push, environment.isSignedIn else { return }
        preferences = (try? await push.notificationPreferences()) ?? .all
        hasLoaded = true
    }

    private func save(_ updated: NotificationPreferences) async {
        guard let push = environment.push else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await push.setNotificationPreferences(updated)
        } catch {
            // Put the toggle back where it was rather than showing a state
            // the server does not agree with.
            preferences = (try? await push.notificationPreferences()) ?? .all
        }
    }
}
