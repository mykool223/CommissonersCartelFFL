import SwiftUI
import CartelCore

/// One matchup, player by player.
///
/// Stacked by team rather than side by side: two lineups across a phone leaves
/// room for about nine characters of a name, and "Amon-Ra St. Brown" is not
/// nine characters. The totals sit at the top so the comparison people
/// actually came for does not need scrolling.
struct MatchupBoxscoreView: View {
    let matchup: Matchup
    let board: MatchupsViewModel.Board

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.medium) {
                header

                lineup(for: matchup.home)
                if let away = matchup.away {
                    lineup(for: away)
                }
            }
            .padding(Theme.Spacing.large)
        }
        .screenStyle()
        .navigationTitle("Week \(matchup.week)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        Card {
            HStack(alignment: .top) {
                totalColumn(for: matchup.home, alignment: .leading)
                Spacer(minLength: Theme.Spacing.small)
                VStack(spacing: 2) {
                    Text(statusLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(matchup.status == .inProgress ? Color.brand : .secondary)
                    if matchup.isComplete, matchup.margin > 0 {
                        Text("by \(matchup.margin.pointsText)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: Theme.Spacing.small)
                if let away = matchup.away {
                    totalColumn(for: away, alignment: .trailing)
                }
            }
        }
    }

    private var statusLabel: String {
        switch matchup.status {
        case .scheduled: "SCHEDULED"
        case .inProgress: "IN PROGRESS"
        case .final: "FINAL"
        }
    }

    private func totalColumn(
        for side: MatchupSide, alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(board.team(side.teamID)?.name ?? "Team \(side.teamID)")
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
            Text(side.points.pointsText)
                .font(.title3.monospacedDigit().weight(.bold))
            if let projected = side.projectedPoints {
                Text("proj \(projected.pointsText)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    @ViewBuilder
    private func lineup(for side: MatchupSide) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                HStack {
                    Text(board.team(side.teamID)?.name ?? "Team \(side.teamID)")
                        .font(.subheadline.weight(.bold))
                    Spacer(minLength: 0)
                    Text(side.points.pointsText)
                        .font(.subheadline.monospacedDigit().weight(.bold))
                }

                if side.roster.isEmpty {
                    // Not an error: a week ESPN has not posted lineups for
                    // looks exactly like this, and saying so is better than an
                    // empty card that reads as a bug.
                    Text("ESPN hasn't posted a lineup for this week yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(side.starters) { entry in
                        PlayerRow(entry: entry)
                    }

                    if !side.bench.isEmpty {
                        Text("BENCH")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.top, Theme.Spacing.tight)
                        ForEach(side.bench) { entry in
                            PlayerRow(entry: entry)
                        }
                    }
                }
            }
        }
    }
}

private struct PlayerRow: View {
    let entry: RosterEntry

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Text(entry.slot)
                .font(.caption2.weight(.bold))
                .foregroundStyle(entry.isStarter ? Color.brand : .secondary)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                Text(entry.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(entry.position)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(entry.points.pointsText)
                .font(.subheadline.monospacedDigit().weight(entry.isStarter ? .semibold : .regular))
                .foregroundStyle(entry.isStarter ? .primary : .secondary)
        }
        // The bench is context, not the story, so it recedes rather than
        // competing with the lineup that is actually scoring.
        .opacity(entry.isStarter ? 1 : 0.6)
    }
}
