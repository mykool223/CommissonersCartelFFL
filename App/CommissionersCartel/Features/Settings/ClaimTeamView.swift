import SwiftUI
import CartelCore

/// Lets a signed-in member say which ESPN team is theirs.
///
/// ESPN publishes no email addresses, so the app cannot work out that
/// you@example.com is Homicidal Pigeons. One tap, once, from the real roster.
struct ClaimTeamView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [MembersViewModel.Entry] = []
    @State private var claimedSWID: String?
    @State private var isLoading = true
    @State private var error: String?
    @State private var claiming: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    LoadingPlaceholder()
                } else if entries.isEmpty {
                    EmptyStateView(
                        message: "Couldn't load the league roster.",
                        systemImage: "person.crop.circle.badge.questionmark"
                    )
                } else {
                    list
                }
            }
            .screenStyle()
            .navigationTitle("Which team is yours?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.medium) {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Color.loss)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(entries) { entry in
                    Button {
                        Task { await claim(entry) }
                    } label: {
                        Card {
                            HStack(spacing: Theme.Spacing.medium) {
                                TeamLogoView(
                                    logoURL: entry.team?.logoURL,
                                    fallbackInitials: entry.manager.initials
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.team?.name ?? entry.manager.fullName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(entry.manager.fullName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if claiming == entry.manager.id {
                                    ProgressView()
                                } else if claimedSWID == entry.manager.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.win)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.Spacing.large)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        let model = MembersViewModel()
        await model.load(using: environment)
        entries = model.allEntries
        claimedSWID = try? await environment.chat?.claimedESPNTeam()
    }

    private func claim(_ entry: MembersViewModel.Entry) async {
        error = nil
        claiming = entry.manager.id
        defer { claiming = nil }

        do {
            try await environment.chat?.claimESPNTeam(swid: entry.manager.id)
            claimedSWID = entry.manager.id
            dismiss()
        } catch let failure as CartelError {
            error = failure.errorDescription ?? "Couldn't claim that team."
        } catch {
            self.error = error.localizedDescription
        }
    }
}
