import SwiftUI
import CartelCore

/// Weekly scoreboard, with the commissioner's recap inline under any matchup
/// that has one.
struct MatchupsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model = MatchupsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.medium) {
                    if environment.isUsingMockLeagueData {
                        SampleDataBanner(
                            detail: "Showing a sample schedule. Add your ESPN league id in Settings."
                        )
                    }

                    LoadableView(
                        state: model.state,
                        emptyMessage: "No games scheduled for this week.",
                        retry: { await model.load(using: environment) }
                    ) { board in
                        weekPicker(board: board)

                        if board.matchups.isEmpty {
                            EmptyStateView(
                                message: "No games scheduled for week \(model.selectedWeek ?? board.league.currentWeek).",
                                systemImage: "calendar"
                            )
                        } else {
                            ForEach(board.matchups) { matchup in
                                MatchupCard(matchup: matchup, board: board)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.large)
            }
            .screenStyle()
            .navigationTitle("Matchups")
            .refreshable { await model.load(using: environment, showSpinner: false) }
            .task { await model.load(using: environment) }
        }
    }

    private func weekPicker(board: MatchupsViewModel.Board) -> some View {
        // Include playoff weeks: the schedule runs past the regular season.
        let weeks = Array(1...max(board.league.currentWeek, board.league.regularSeasonWeeks))
        return Picker("Week", selection: Binding(
            get: { model.selectedWeek ?? board.league.currentWeek },
            set: { week in Task { await model.selectWeek(week, using: environment) } }
        )) {
            ForEach(weeks, id: \.self) { week in
                Text("Week \(week)").tag(week)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MatchupCard: View {
    let matchup: Matchup
    let board: MatchupsViewModel.Board

    var body: some View {
        Card {
            HStack {
                Pill(
                    text: matchup.isComplete ? "Final" : "In progress",
                    tint: matchup.isComplete ? .secondary : .brand
                )
                Spacer(minLength: 0)
                if matchup.isComplete, matchup.margin > 0 {
                    Text("by \(matchup.margin.pointsText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if matchup.isBye {
                TeamScoreRow(side: matchup.home, board: board, isWinner: false)
                Text("Bye week")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                TeamScoreRow(
                    side: matchup.home,
                    board: board,
                    isWinner: matchup.winningTeamID == matchup.home.teamID
                )
                Divider()
                if let away = matchup.away {
                    TeamScoreRow(
                        side: away,
                        board: board,
                        isWinner: matchup.winningTeamID == away.teamID
                    )
                }
            }

            if let recap = board.recap(for: matchup) {
                Divider()
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(recap.headline)
                        .font(.subheadline.weight(.semibold))
                    Text(recap.body)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct TeamScoreRow: View {
    let side: MatchupSide
    let board: MatchupsViewModel.Board
    let isWinner: Bool

    /// True once there are points on the board for this side.
    private var hasStarted: Bool { side.points > 0 }

    var body: some View {
        let team = board.team(side.teamID)
        HStack(spacing: Theme.Spacing.medium) {
            // The whole abbreviation, not the first two letters — "BEAR" and
            // "TRAP" are recognisable, "BE" and "TR" are not.
            InitialsAvatar(initials: team?.abbreviation.uppercased() ?? "?", size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(team?.name ?? "Team \(side.teamID)")
                    .font(.subheadline.weight(isWinner ? .bold : .regular))
                    .lineLimit(1)
                if let record = team?.record, record.gamesPlayed > 0 {
                    Text(record.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                // A game that hasn't kicked off has 0.0 points, which reads as
                // "scored nothing" rather than "hasn't started". Show an em
                // dash instead and let the projection carry the information.
                if hasStarted {
                    Text(side.points.pointsText)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(isWinner ? Color.win : .primary)
                } else {
                    Text("—")
                        .font(.headline)
                        .foregroundStyle(.tertiary)
                }
                // Only meaningful before the games are final.
                if let projected = side.projectedPoints {
                    Text("proj \(projected.pointsText)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    MatchupsView()
        .environment(AppEnvironment.preview)
}
