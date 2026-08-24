import SwiftUI
import CartelCore

struct MemberDetailView: View {
    let entry: MembersViewModel.Entry

    @Environment(AppEnvironment.self) private var environment
    /// The app account behind this ESPN manager, if they have one. An ESPN
    /// manager who has never signed in has nowhere for a message to arrive,
    /// so the button is absent rather than offering to send into a void.
    @State private var account: LeagueMember?
    @State private var conversation: Conversation?
    @State private var chatModel = DirectMessagesViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.large) {
                header

                if let account, account.id != environment.session?.userID {
                    Button {
                        conversation = chatModel.conversation(
                            with: account.id, named: account.displayName
                        )
                    } label: {
                        Label(
                            "Message \(entry.manager.fullName.split(separator: " ").first.map(String.init) ?? entry.manager.fullName)",
                            systemImage: "envelope"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brand)
                }

                if let bio = entry.bio {
                    Card {
                        HStack(spacing: Theme.Spacing.small) {
                            Image(systemName: "quote.opening")
                                .font(.caption)
                                .foregroundStyle(Color.brand)
                            Text(bio.title.uppercased())
                                .font(.caption.weight(.bold))
                                .kerning(1.2)
                                .foregroundStyle(Color.brand)
                        }
                        Text(bio.bio)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let team = entry.team {
                    Card {
                        Text("Season")
                            .font(.subheadline.weight(.semibold))
                        StatRow(label: "Record", value: team.record.summary)
                        StatRow(
                            label: "Win %",
                            value: team.record.winPercentage
                                .formatted(.percent.precision(.fractionLength(1)))
                        )
                        StatRow(label: "Points for", value: team.record.pointsFor.pointsText)
                        StatRow(label: "Points against", value: team.record.pointsAgainst.pointsText)
                        StatRow(
                            label: "Differential",
                            value: team.record.pointDifferential.signedPointsText,
                            tint: team.record.pointDifferential >= 0 ? .win : .loss
                        )
                        if let seed = team.playoffSeed {
                            StatRow(label: "Standing", value: "#\(seed)")
                        }
                    }
                } else {
                    Card {
                        Text("This member doesn't own a team in the current season.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(Theme.Spacing.large)
        }
        .screenStyle()
        .navigationTitle(entry.manager.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: entry.manager.id) { await resolveAccount() }
        .navigationDestination(item: $conversation) { conversation in
            ConversationView(conversation: conversation, model: chatModel)
        }
    }

    /// Matches this ESPN manager to an app account by the team they claimed,
    /// rather than by name — two members share a first name, and a display
    /// name is whatever somebody typed.
    private func resolveAccount() async {
        guard let chat = environment.chat, environment.isSignedIn else { return }
        let members = (try? await chat.members()) ?? []
        let managerID = entry.manager.id.uppercased()
        account = members.first { member in
            member.espnSWID?.trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() == managerID
        }
        if account != nil { await chatModel.load(using: environment) }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.small) {
            TeamLogoView(
                logoURL: entry.team?.logoURL,
                fallbackInitials: entry.manager.initials,
                size: 72
            )
            Text(entry.team?.name ?? entry.manager.fullName)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("@\(entry.manager.displayName)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if entry.manager.isCommissioner {
                Pill(text: "Commissioner", tint: .brand)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatRow: View {
    let label: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.footnote.monospacedDigit().weight(.medium))
                .foregroundStyle(tint)
        }
    }
}

#Preview {
    NavigationStack {
        MemberDetailView(
            entry: MembersViewModel.Entry(
                manager: MockData.managers[0],
                team: MockData.teams[0]
            )
        )
    }
}
