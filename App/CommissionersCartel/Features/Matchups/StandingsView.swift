import SwiftUI
import CartelCore

/// League table, grouped by division when the league has them.
struct StandingsView: View {
    let board: MatchupsViewModel.Board

    var body: some View {
        LazyVStack(spacing: Theme.Spacing.medium) {
            if board.teamsByID.isEmpty {
                EmptyStateView(message: "No teams found.", systemImage: "list.number")
            } else {
                ForEach(board.standings) { group in
                    if let title = group.title {
                        HStack {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Theme.Spacing.tight)
                        .padding(.top, Theme.Spacing.small)
                    }

                    Card {
                        StandingsHeader()
                        ForEach(Array(group.teams.enumerated()), id: \.element.id) { index, team in
                            Divider()
                            StandingsRow(rank: index + 1, team: team)
                        }
                    }
                }
            }
        }
    }
}

private struct StandingsHeader: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Text("#")
                .frame(width: 18, alignment: .leading)
            Text("Team")
            Spacer(minLength: 0)
            Text("W-L")
                .frame(width: 46, alignment: .trailing)
            Text("PF")
                .frame(width: 58, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .textCase(.uppercase)
        .foregroundStyle(.secondary)
    }
}

private struct StandingsRow: View {
    let rank: Int
    let team: Team

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Text("\(rank)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)

            TeamLogoView(
                logoURL: team.logoURL,
                fallbackInitials: team.abbreviation.uppercased(),
                size: 26
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(team.name)
                    .font(.subheadline)
                    .lineLimit(1)
                // Only worth the row height once games have been played.
                if team.record.gamesPlayed > 0 {
                    Text("\(team.record.pointDifferential.signedPointsText) diff")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(
                            team.record.pointDifferential >= 0 ? Color.win : Color.loss
                        )
                }
            }

            Spacer(minLength: 0)

            Text(team.record.summary)
                .font(.subheadline.monospacedDigit())
                .frame(width: 46, alignment: .trailing)

            Text(team.record.pointsFor.pointsText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
