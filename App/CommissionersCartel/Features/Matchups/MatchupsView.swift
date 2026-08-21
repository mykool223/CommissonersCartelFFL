import SwiftUI
import CartelCore

/// Scoreboard, recap and standings — all driven by one ESPN payload, so
/// switching between them costs nothing.
enum MatchupsSection: String, TabSection {
    case scoreboard
    case recap
    case standings
    case nfl

    var title: String {
        switch self {
        case .scoreboard: "Scoreboard"
        case .recap: "Weekly recap"
        case .standings: "Standings"
        case .nfl: "NFL scores"
        }
    }

    var systemImage: String {
        switch self {
        case .scoreboard: "sportscourt"
        case .recap: "trophy"
        case .standings: "list.number"
        case .nfl: "football"
        }
    }

    /// NFL scores are public and need no league configuration, so that section
    /// works even when everything else is unconfigured or erroring.
    var needsLeagueData: Bool { self != .nfl }
}

struct MatchupsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model = MatchupsViewModel()
    @State private var section: MatchupsSection = .initial(default: .scoreboard)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.medium) {
                    if section.needsLeagueData, environment.isUsingMockLeagueData {
                        SampleDataBanner(
                            detail: "Showing a sample schedule. Add your ESPN league id in Settings."
                        )
                    }

                    if section == .nfl {
                        nflScores
                    } else {
                        LoadableView(
                        state: model.state,
                        emptyMessage: "No games scheduled for this week.",
                        retry: { await model.load(using: environment) }
                    ) { board in
                        // The week applies to the scoreboard and the recap;
                        // standings are season-long.
                        if section != .standings {
                            weekPicker(board: board)
                        }

                        switch section {
                        case .scoreboard: scoreboard(board: board)
                        case .recap: WeeklyRecapView(board: board, awards: board.awards)
                        case .standings: StandingsView(board: board)
                        case .nfl: EmptyView()
                        }
                        }
                    }
                }
                .padding(Theme.Spacing.large)
            }
            .screenStyle()
            .sectionPicker($section)
            .refreshable { await model.refresh(using: environment) }
            .task {
                await model.load(using: environment)
                if section == .recap {
                    await model.showMostRecentPlayedWeek(using: environment)
                }
            }
            .onChange(of: section) { _, newSection in
                Task {
                    switch newSection {
                    case .recap:
                        await model.showMostRecentPlayedWeek(using: environment)
                    case .nfl:
                        // Scores move while the app is open, so re-read on
                        // every visit rather than only on first appearance.
                        await model.loadNFLScores(using: environment)
                    default:
                        break
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var nflScores: some View {
        if let scoreboard = model.nflScoreboard {
            NFLScoresView(scoreboard: scoreboard)
        } else {
            LoadingPlaceholder()
        }
    }

    @ViewBuilder
    private func scoreboard(board: MatchupsViewModel.Board) -> some View {
        if board.matchups.isEmpty {
            EmptyStateView(
                message: "No games scheduled for week \(board.week).",
                systemImage: "calendar"
            )
        } else {
            ForEach(board.matchups) { matchup in
                MatchupCard(matchup: matchup, board: board)
            }
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

    private var statusLabel: String {
        switch matchup.status {
        case .scheduled: "Scheduled"
        case .inProgress: "In progress"
        case .final: "Final"
        }
    }

    private var statusTint: Color {
        switch matchup.status {
        case .scheduled: .secondary
        case .inProgress: .brand
        case .final: .secondary
        }
    }

    var body: some View {
        Card {
            HStack {
                Pill(text: statusLabel, tint: statusTint)
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
            // Falls back to the whole abbreviation, not the first two letters —
            // "BEAR" and "TRAP" are recognisable, "BE" and "TR" are not. Most
            // teams land on that fallback: only managers who uploaded their own
            // image have a logo the app can decode.
            TeamLogoView(
                logoURL: team?.logoURL,
                fallbackInitials: team?.abbreviation.uppercased() ?? "?",
                size: 34
            )

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
