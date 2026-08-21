import SwiftUI
import CartelCore

/// Who's in the league, in standings order.
struct MembersView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model = MembersViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.medium) {
                    if environment.isUsingMockLeagueData {
                        SampleDataBanner(
                            detail: "Showing sample managers. Add your ESPN league id in Settings."
                        )
                    }

                    LoadableView(
                        state: model.state,
                        emptyMessage: "No managers found in this league.",
                        retry: { await model.load(using: environment) }
                    ) { entries in
                        ForEach(entries) { entry in
                            NavigationLink(value: entry.manager.id) {
                                MemberRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(Theme.Spacing.large)
            }
            .screenStyle()
            .navigationTitle("Members")
            .navigationDestination(for: String.self) { managerID in
                if let entry = model.state.value?.first(where: { $0.id == managerID }) {
                    MemberDetailView(entry: entry)
                } else {
                    EmptyStateView(message: "That member is no longer in the league.")
                }
            }
            .refreshable { await model.load(using: environment, showSpinner: false) }
            .task { await model.load(using: environment) }
        }
    }
}

private struct MemberRow: View {
    let entry: MembersViewModel.Entry

    var body: some View {
        Card {
            HStack(spacing: Theme.Spacing.medium) {
                if let seed = entry.team?.playoffSeed {
                    Text("\(seed)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }

                InitialsAvatar(initials: entry.manager.initials)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.small) {
                        Text(entry.team?.name ?? entry.manager.fullName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if entry.manager.isCommissioner {
                            Pill(text: "Commish", tint: .brand)
                        }
                    }
                    Text(entry.manager.fullName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let record = entry.team?.record, record.gamesPlayed > 0 {
                    Text(record.summary)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    MembersView()
        .environment(AppEnvironment.preview)
}
