import SwiftUI
import CartelCore

/// The week's confidence pool: pick every game, weight every pick.
///
/// Tapping a team picks it and assigns the highest weight left, so working
/// down the list from the game you are surest about needs one tap per game
/// rather than a pick and a separate number. The weights can still be changed
/// afterwards, which is what the menu on each row is for.
struct PickemView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model = PickemViewModel()
    @State private var showingTable = false

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            case .failed(let message):
                ContentUnavailableView("Couldn't load the games", systemImage: "football",
                                       description: Text(message))
            case .ready where model.games.isEmpty:
                ContentUnavailableView(
                    "No games yet",
                    systemImage: "football",
                    description: Text("The week's fixtures appear once the NFL posts them.")
                )
            case .ready:
                board
            }
        }
        .task(id: environment.session?.userID) {
            model.attach(environment: environment)
            await model.load(using: environment)
        }
    }

    private var board: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.small) {
                header

                ForEach(model.games) { game in
                    PickemRow(
                        game: game,
                        pick: model.pick(for: game),
                        available: model.availableWeights(for: game),
                        onChoose: { model.choose(team: $0, in: game) },
                        onWeigh: { model.weigh(game, at: $0) }
                    )
                }

                if !model.standings.isEmpty {
                    table
                }
            }
            .padding(Theme.Spacing.large)
        }
        .refreshable { await model.load(using: environment, showSpinner: false) }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Week \(model.week)")
                .font(.headline)
            Text(model.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if model.isSaving {
                ProgressView().controlSize(.small)
            } else if let error = model.saveError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, Theme.Spacing.small)
    }

    private var table: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("THIS WEEK")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, Theme.Spacing.large)

            ForEach(Array(model.standings.enumerated()), id: \.element.id) { index, row in
                Card {
                    HStack {
                        Text("\(index + 1)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 22, alignment: .trailing)
                        Text(row.displayName)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(row.correct)/\(row.decided)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("\(row.points)")
                            .font(.headline.monospacedDigit())
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
    }
}

/// One fixture: two teams to choose between, and what the pick is worth.
private struct PickemRow: View {
    let game: PickemGame
    let pick: PickemPick?
    let available: [Int]
    let onChoose: (String) -> Void
    let onWeigh: (Int) -> Void

    var body: some View {
        Card {
            VStack(spacing: Theme.Spacing.small) {
                HStack(spacing: Theme.Spacing.small) {
                    team(game.awayAbbreviation, game.awayName)
                    Text("at")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    team(game.homeAbbreviation, game.homeName)
                }

                HStack {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    weight
                }
            }
        }
    }

    private func team(_ abbreviation: String, _ name: String) -> some View {
        let chosen = pick?.chosenAbbreviation == abbreviation
        let won = game.winnerAbbreviation == abbreviation
        return Button {
            onChoose(abbreviation)
        } label: {
            Text(abbreviation)
                .font(.subheadline.weight(chosen ? .bold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    chosen ? Color.brand.opacity(0.18) : Color.cardBackground,
                    in: .rect(cornerRadius: Theme.Radius.card)
                )
                .overlay(alignment: .topTrailing) {
                    if game.isFinal && won {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .padding(4)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(game.isLocked)
        .accessibilityLabel(name)
    }

    /// Locked games say why; open ones say when they go.
    private var detail: String {
        if game.isFinal {
            return game.winnerAbbreviation.map { "Final · \($0)" } ?? "Final · tie"
        }
        if game.isLocked { return "Started · picks locked" }
        return game.kickoff.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    @ViewBuilder private var weight: some View {
        if game.isLocked {
            if let pick {
                Text("\(pick.confidence) pts")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        } else {
            Menu {
                ForEach(available, id: \.self) { value in
                    Button("\(value) points") { onWeigh(value) }
                }
            } label: {
                Text(pick.map { "\($0.confidence) pts" } ?? "Weight")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.brand.opacity(0.15), in: .capsule)
            }
            .disabled(pick == nil)
        }
    }
}
