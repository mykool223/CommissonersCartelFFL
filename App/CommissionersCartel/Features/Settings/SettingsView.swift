import SwiftUI
import CartelCore

/// Setup status and ESPN credentials.
///
/// The league id and Supabase keys are build settings (see Config/*.xcconfig),
/// so this screen reports them read-only. Only the ESPN session cookies are
/// editable here, because they're per-person secrets that must not be baked
/// into the app.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var espnS2: String = KeychainStore.string(for: .espnS2) ?? ""
    @State private var swid: String = KeychainStore.string(for: .espnSWID) ?? ""
    @State private var didSave = false

    var body: some View {
        NavigationStack {
            Form {
                Section("League") {
                    LabeledContent("Season", value: String(environment.season))
                    LabeledContent(
                        "ESPN league",
                        value: environment.configuration.espnLeagueID.isEmpty
                            ? "Not set" : environment.configuration.espnLeagueID
                    )
                    StatusRow(
                        title: "League data",
                        isLive: !environment.isUsingMockLeagueData,
                        liveDetail: "Live from ESPN",
                        mockDetail: "Sample data"
                    )
                    StatusRow(
                        title: "News & polls",
                        isLive: !environment.isUsingMockContent,
                        liveDetail: "Live from Supabase",
                        mockDetail: "Sample data"
                    )
                }

                Section {
                    SecureField("espn_s2", text: $espnS2)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                    SecureField("SWID", text: $swid)
                        .textContentType(.password)
                        .autocorrectionDisabled()

                    Button("Save credentials") { save() }
                        .disabled(espnS2.isEmpty || swid.isEmpty)

                    if KeychainStore.espnCredentials != nil {
                        Button("Remove credentials", role: .destructive) { clear() }
                    }
                } header: {
                    Text("Private league access")
                } footer: {
                    Text("""
                    Only needed if your league is private. Sign in to ESPN in a \
                    desktop browser, open developer tools, and copy the `espn_s2` \
                    and `SWID` cookies. They're stored in the iOS Keychain and \
                    never leave this device.
                    """)
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.versionText)
                } header: {
                    Text("About")
                } footer: {
                    if environment.configuration.isFullyMocked {
                        Text("""
                        No backends are configured, so every screen is showing \
                        sample data. See docs/SUPABASE_SETUP.md and \
                        docs/ESPN_API.md to connect the real thing.
                        """)
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Saved", isPresented: $didSave) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Pull to refresh any screen to load your league.")
            }
        }
    }

    private func save() {
        KeychainStore.set(espnS2.trimmingCharacters(in: .whitespacesAndNewlines), for: .espnS2)
        KeychainStore.set(swid.trimmingCharacters(in: .whitespacesAndNewlines), for: .espnSWID)
        environment.reloadESPNCredentials()
        didSave = true
    }

    private func clear() {
        KeychainStore.set(nil, for: .espnS2)
        KeychainStore.set(nil, for: .espnSWID)
        espnS2 = ""
        swid = ""
        environment.reloadESPNCredentials()
    }
}

private struct StatusRow: View {
    let title: String
    let isLive: Bool
    let liveDetail: String
    let mockDetail: String

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 0)
            Label(
                isLive ? liveDetail : mockDetail,
                systemImage: isLive ? "checkmark.circle.fill" : "circle.dashed"
            )
            .font(.footnote)
            .foregroundStyle(isLive ? Color.win : .secondary)
        }
    }
}

private extension Bundle {
    var versionText: String {
        let short = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(AppEnvironment.preview)
}
