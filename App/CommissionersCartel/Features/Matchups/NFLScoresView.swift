import SwiftUI
import CartelCore

/// Real NFL games, live.
///
/// Separate from the league's own matchups but housed in the same tab, because
/// these are the games the fantasy scores come out of.
struct NFLScoresView: View {
    let scoreboard: NFLScoreboard

    var body: some View {
        LazyVStack(spacing: Theme.Spacing.medium) {
            HStack(spacing: Theme.Spacing.small) {
                Text(scoreboard.weekTitle)
                    .font(.subheadline.weight(.semibold))
                if scoreboard.hasLiveGames {
                    LivePill()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.tight)

            if scoreboard.games.isEmpty {
                EmptyStateView(message: "No NFL games this week.", systemImage: "football")
            } else {
                ForEach(scoreboard.gamesInReadingOrder) { game in
                    NFLGameCard(game: game)
                }
            }
        }
    }
}

/// Pulses so a live game is obvious without reading the status text.
private struct LivePill: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.loss)
                .frame(width: 6, height: 6)
                .opacity(dimmed ? 0.3 : 1)
            Text("Live")
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
        }
        .foregroundStyle(Color.loss)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                dimmed = true
            }
        }
        .accessibilityLabel("Games in progress")
    }
}

private struct NFLGameCard: View {
    let game: NFLGame

    var body: some View {
        Card {
            HStack {
                Pill(text: statusText, tint: statusTint)
                Spacer(minLength: 0)
                if game.state == .scheduled, let start = game.startDate {
                    Text(start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            NFLTeamRow(side: game.away, game: game)
            Divider()
            NFLTeamRow(side: game.home, game: game)
        }
    }

    private var statusText: String {
        switch game.state {
        case .scheduled: "Scheduled"
        case .inProgress: game.statusDetail.isEmpty ? "In progress" : game.statusDetail
        case .final: game.statusDetail.isEmpty ? "Final" : game.statusDetail
        }
    }

    private var statusTint: Color {
        switch game.state {
        case .scheduled: .secondary
        case .inProgress: .loss
        case .final: .secondary
        }
    }
}

private struct NFLTeamRow: View {
    let side: NFLGame.Side
    let game: NFLGame

    private var isLeading: Bool {
        game.leadingAbbreviation == side.abbreviation
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            NFLTeamLogo(url: side.logoURL, abbreviation: side.abbreviation)

            VStack(alignment: .leading, spacing: 1) {
                Text(side.name)
                    .font(.subheadline.weight(isLeading ? .bold : .regular))
                    .lineLimit(1)
                if let record = side.record {
                    Text(record)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if let score = side.score {
                Text("\(score)")
                    .font(.title3.monospacedDigit().weight(isLeading ? .bold : .regular))
                    .foregroundStyle(isLeading ? Color.win : .primary)
            } else {
                // Before kickoff there is no score to show; an em dash beats a
                // zero, which reads as "scored nothing".
                Text("—")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// ESPN's scoreboard logos are PNG on a public CDN, so unlike the fantasy
/// team logos these need no proxy and always decode.
private struct NFLTeamLogo: View {
    let url: URL?
    let abbreviation: String
    var size: CGFloat = 34

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                InitialsAvatar(initials: abbreviation, size: size)
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = await LogoCache.shared.image(for: url, headers: [:])
        }
    }
}
