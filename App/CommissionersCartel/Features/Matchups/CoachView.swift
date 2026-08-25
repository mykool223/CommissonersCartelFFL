import SwiftUI
import CartelCore

/// Coach Landry: ask about your own team.
///
/// The function behind this is given the real roster, the real projections and
/// the solved best lineup — it reasons about numbers rather than recalling
/// them, which is what keeps it from inventing a player who does not exist.
struct CoachView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model = CoachViewModel()
    @State private var draft = ""

    /// Openers, so nobody faces an empty box wondering what to type.
    private let prompts = [
        "Who should I start at flex?",
        "Is my lineup right this week?",
    ]

    var body: some View {
        VStack(spacing: 0) {
            if model.turns.isEmpty && !model.isBusy {
                ContentUnavailableView {
                    Label("Coach Landry", image: "CoachIcon")
                } description: {
                    Text("Ask about your own team. He has your roster and this "
                         + "week's projections in front of him.")
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.small) {
                            ForEach(model.turns) { turn in
                                Card {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(turn.isCoach ? "COACH LANDRY" : "YOU")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(
                                                turn.isCoach ? Color.brand : .secondary
                                            )
                                        Text(turn.text)
                                            .font(.callout)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .id(turn.id)
                            }
                            if model.isBusy { ProgressView().padding() }
                        }
                        .padding(Theme.Spacing.large)
                    }
                    .onChange(of: model.turns.count) {
                        if let last = model.turns.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }

            if model.turns.isEmpty {
                HStack(spacing: Theme.Spacing.small) {
                    ForEach(prompts, id: \.self) { prompt in
                        Button {
                            Task { await model.ask(prompt, using: environment) }
                        } label: {
                            Text(prompt)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.cardBackground, in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Spacing.medium)
            }

            // Always visible, not only on the empty state: the warning is
            // least useful once somebody is deep in a conversation and most
            // likely to be acted on there.
            Text("Coach Landry can be wrong. Projections are estimates and he can misread them — check before you act on it. Expert consensus data from FantasyPros.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Spacing.large)

            HStack(spacing: Theme.Spacing.small) {
                TextField("Ask Coach Landry", text: $draft, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(.horizontal, Theme.Spacing.medium)
                    .padding(.vertical, Theme.Spacing.small)
                    .background(Color.cardBackground, in: .capsule)

                Button {
                    let question = draft
                    draft = ""
                    Task { await model.ask(question, using: environment) }
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(
                    draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy
                )
            }
            .padding(Theme.Spacing.medium)
        }
        .task {
            // Bring back the conversation from previous sessions, once.
            await model.loadHistory(using: environment)
        }
    }
}
