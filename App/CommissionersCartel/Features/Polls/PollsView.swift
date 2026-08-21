import SwiftUI
import CartelCore

/// League polls. Results stay hidden until you vote or the poll closes, so
/// early votes don't anchor everyone else.
struct PollsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model = PollsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if !environment.isSignedIn {
                    signedOutState
                } else if !environment.isLeagueMember {
                    notAMemberState
                } else {
                    pollList
                }
            }
            .screenStyle()
            .navigationTitle("Polls")
            // Keyed on the session: polls require a signed-in member, and
            // restoration finishes after this view first appears. A bare
            // .task would load once while signed out, hit a permission error,
            // and never retry.
            .task(id: environment.session?.userID) {
                await model.load(using: environment)
            }
            .alert(
                "Vote not saved",
                isPresented: Binding(
                    get: { model.voteError != nil },
                    set: { if !$0 { model.voteError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { model.voteError = nil }
            } message: {
                Text(model.voteError ?? "")
            }
        }
    }

    /// Voting needs to know who is voting, so this is a sign-in prompt rather
    /// than an error. Previously the failed request surfaced as CartelError
    /// .notAuthorized, which the shared error view renders as "This league is
    /// private. Add your ESPN credentials in Settings" — wrong twice over, and
    /// it sends people to a screen that cannot fix it.
    private var signedOutState: some View {
        ContentUnavailableView {
            Label("Sign in to vote", systemImage: "chart.bar")
        } description: {
            Text("Polls are for league members. Sign in from Settings — it takes a moment and there's no password.")
        }
    }

    private var notAMemberState: some View {
        ContentUnavailableView {
            Label("Not on the roster", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text("You're signed in as \(environment.session?.email ?? "this account"), but that address isn't on the league list. Ask the commissioner to add you.")
        }
    }

    private var pollList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.medium) {
                if environment.isUsingMockContent {
                    SampleDataBanner(
                        detail: "Votes are stored on this device only until Supabase is connected."
                    )
                }

                LoadableView(
                    state: model.state,
                    emptyMessage: "No polls yet. Start one and settle an argument.",
                    retry: { await model.load(using: environment) }
                ) { polls in
                    ForEach(polls) { poll in
                        PollCard(poll: poll) { optionID in
                            await model.vote(
                                pollID: poll.id, optionID: optionID, using: environment
                            )
                        }
                    }
                }
            }
            .padding(Theme.Spacing.large)
        }
        .refreshable { await model.load(using: environment, showSpinner: false) }
    }
}

struct PollCard: View {
    let poll: Poll
    let onVote: (UUID) async -> Void

    var body: some View {
        let closed = poll.isClosed(asOf: .now)
        // Hide the tally until the reader has committed to an answer.
        let showResults = poll.hasVoted || closed

        Card {
            HStack(spacing: Theme.Spacing.small) {
                if let week = poll.week {
                    Pill(text: "Week \(week)", tint: .brand)
                }
                if closed {
                    Pill(text: "Closed")
                }
                Spacer(minLength: 0)
                Text("\(poll.totalVotes) \(poll.totalVotes == 1 ? "vote" : "votes")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(poll.question)
                .font(.headline)

            VStack(spacing: Theme.Spacing.small) {
                ForEach(poll.options) { option in
                    PollOptionRow(
                        option: option,
                        share: poll.share(of: option),
                        isSelected: poll.myVoteOptionID == option.id,
                        showResults: showResults,
                        isEnabled: !closed
                    ) {
                        await onVote(option.id)
                    }
                }
            }

            HStack {
                Text("Started by \(poll.createdByName)")
                if let closesAt = poll.closesAt, !closed {
                    Text("· closes \(closesAt.relativeText)")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }
}

private struct PollOptionRow: View {
    let option: PollOption
    let share: Double
    let isSelected: Bool
    let showResults: Bool
    let isEnabled: Bool
    let onTap: () async -> Void

    var body: some View {
        Button {
            Task { await onTap() }
        } label: {
            ZStack(alignment: .leading) {
                // Result bar, drawn behind the label.
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: Theme.Radius.card - 4)
                        .fill(Color.brand.opacity(isSelected ? 0.30 : 0.15))
                        .frame(width: showResults ? proxy.size.width * share : 0)
                }
                .animation(.easeOut(duration: 0.35), value: share)
                .animation(.easeOut(duration: 0.35), value: showResults)

                HStack {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.brand)
                    }
                    Text(option.label)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    if showResults {
                        Text(share.formatted(.percent.precision(.fractionLength(0))))
                            .font(.subheadline.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, Theme.Spacing.medium)
            }
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card - 4)
                    .stroke(Color.secondary.opacity(0.2))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(option.label)
        .accessibilityValue(
            showResults
                ? "\(option.voteCount) votes, \(share.formatted(.percent.precision(.fractionLength(0))))"
                : "Not yet voted"
        )
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview {
    PollsView()
        .environment(AppEnvironment.preview)
}
