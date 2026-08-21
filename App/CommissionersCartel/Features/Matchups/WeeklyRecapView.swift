import SwiftUI
import CartelCore

/// The week's superlatives.
///
/// Computed from matchups the app already has — one ESPN payload carries the
/// whole season, so even the week-over-week comparison behind "Most improved"
/// costs no extra request.
struct WeeklyRecapView: View {
    let board: MatchupsViewModel.Board
    let awards: [WeeklyAward]

    var body: some View {
        LazyVStack(spacing: Theme.Spacing.medium) {
            if awards.isEmpty {
                EmptyStateView(
                    message: "Nothing to recap until week \(board.week) is played.",
                    systemImage: "trophy"
                )
            } else {
                ForEach(orderedAwards) { award in
                    AwardCard(award: award, board: board)
                }
            }
        }
    }

    /// A deliberate reading order: the headline results first, the
    /// consolation prizes last.
    private var orderedAwards: [WeeklyAward] {
        let order: [WeeklyAward.Kind] = [
            .highestScore, .biggestBlowout, .closestGame,
            .shootout, .mostImproved, .unluckiest, .luckiest, .lowestScore,
        ]
        return awards.sorted { lhs, rhs in
            (order.firstIndex(of: lhs.kind) ?? .max) < (order.firstIndex(of: rhs.kind) ?? .max)
        }
    }
}

private struct AwardCard: View {
    let award: WeeklyAward
    let board: MatchupsViewModel.Board

    private var team: Team? { board.team(award.teamID) }
    private var opponent: Team? { award.opponentID.flatMap { board.team($0) } }

    var body: some View {
        Card {
            HStack(spacing: Theme.Spacing.medium) {
                Image(systemName: award.kind.systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.brand)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(award.kind.title)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    HStack(spacing: Theme.Spacing.small) {
                        TeamLogoView(
                            logoURL: team?.logoURL,
                            fallbackInitials: team?.abbreviation.uppercased() ?? "?",
                            size: 28
                        )
                        Text(team?.name ?? "Team \(award.teamID)")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }

                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(headlineValue)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.brand)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var headlineValue: String {
        switch award.kind {
        case .biggestBlowout, .closestGame, .mostImproved:
            return "+\(award.value.pointsText)"
        default:
            return award.value.pointsText
        }
    }

    private var detail: String {
        let other = opponent?.name ?? "their opponent"
        switch award.kind {
        case .highestScore:
            return "Best score of the week"
        case .lowestScore:
            return "Nobody scored less"
        case .biggestBlowout:
            return "Beat \(other) by \(award.value.pointsText)"
        case .closestGame:
            return "Edged \(other) by \(award.value.pointsText)"
        case .shootout:
            return "Combined with \(other) for \(award.value.pointsText)"
        case .unluckiest:
            let lostTo = award.secondaryValue.map { " to \($0.pointsText)" } ?? ""
            return "Scored \(award.value.pointsText) and still lost\(lostTo)"
        case .luckiest:
            let beat = award.secondaryValue.map { " past \($0.pointsText)" } ?? ""
            return "Won with \(award.value.pointsText)\(beat)"
        case .mostImproved:
            return "Up \(award.value.pointsText) on last week"
        }
    }
}

private extension WeeklyAward.Kind {
    var title: String {
        switch self {
        case .highestScore: "Team of the week"
        case .lowestScore: "Rough week"
        case .biggestBlowout: "Biggest blowout"
        case .closestGame: "Closest game"
        case .shootout: "Shootout"
        case .unluckiest: "Unluckiest"
        case .luckiest: "Got away with one"
        case .mostImproved: "Most improved"
        }
    }

    var systemImage: String {
        switch self {
        case .highestScore: "trophy.fill"
        case .lowestScore: "arrow.down.circle.fill"
        case .biggestBlowout: "bolt.fill"
        case .closestGame: "scissors"
        case .shootout: "flame.fill"
        case .unluckiest: "cloud.rain.fill"
        case .luckiest: "dice.fill"
        case .mostImproved: "chart.line.uptrend.xyaxis"
        }
    }
}
