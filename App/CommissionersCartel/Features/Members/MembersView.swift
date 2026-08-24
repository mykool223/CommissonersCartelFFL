import SwiftUI
import CartelCore

enum MembersSection: String, TabSection {
    case roster
    case thread
    case messages
    case trophies

    var title: String {
        switch self {
        case .roster: "Members"
        case .thread: "League thread"
        case .messages: "Messages"
        case .trophies: "Trophy case"
        }
    }

    var systemImage: String {
        switch self {
        case .roster: "person.3"
        case .thread: "bubble.left.and.bubble.right"
        case .messages: "envelope"
        case .trophies: "trophy"
        }
    }
}

/// Who's in the league, and what they have to say about it.
struct MembersView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model = MembersViewModel()
    @State private var section: MembersSection = .initial(default: .roster)
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch section {
                case .roster: roster
                case .thread: LeagueChatView()
                case .messages: DirectMessagesView()
                case .trophies: TrophyCaseView()
                }
            }
            .screenStyle()
            .sectionPicker($section)
            .navigationDestination(for: String.self) { managerID in
                if let entry = model.allEntries.first(where: { $0.id == managerID }) {
                    MemberDetailView(entry: entry)
                } else {
                    EmptyStateView(message: "That member is no longer in the league.")
                }
            }
            #if DEBUG
            // `-openMember 4` pushes the detail screen for an ESPN team id, so
            // a screenshot of it can be taken without simulating a tap — the
            // simulator has no way to inject one.
            .onChange(of: model.allEntries.count) { _, _ in
                guard path.isEmpty,
                      let raw = ProcessInfo.processInfo.arguments
                        .drop(while: { $0 != "-openMember" }).dropFirst().first,
                      let teamID = Int(raw),
                      let entry = model.allEntries.first(where: { $0.team?.id == teamID })
                else { return }
                path = [entry.manager.id]
            }
            #endif
        }
    }

    private var roster: some View {
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
                    ) { groups in
                        ForEach(groups) { group in
                            if let title = group.title {
                                DivisionHeader(title: title, teamCount: group.entries.count)
                            }
                            ForEach(group.entries) { entry in
                                NavigationLink(value: entry.manager.id) {
                                    MemberRow(entry: entry)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.large)
            }
            .refreshable { await model.refresh(using: environment) }
            .task { await model.load(using: environment) }
    }
}

/// Divider between divisions. Deliberately not a pinned section header — the
/// list is twelve rows, and a sticky header would cost more than it gives.
private struct DivisionHeader: View {
    let title: String
    let teamCount: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text("\(teamCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.tight)
        .padding(.top, Theme.Spacing.small)
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

                TeamLogoView(
                    logoURL: entry.team?.logoURL,
                    fallbackInitials: entry.manager.initials
                )

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
