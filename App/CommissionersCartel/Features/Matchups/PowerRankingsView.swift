import SwiftUI
import CartelCore

/// The league power ranking, as FantasyPros' league analyzer scores it.
///
/// Not computed here. Their score grades a whole roster with a value model
/// their public API does not expose, so the commissioner reads it off their
/// site each week and it is stored verbatim. Saying where it comes from
/// matters: it will disagree with the lineup strength the coach quotes, and
/// somebody is entitled to know why.
struct PowerRankingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var rankings: [PowerRanking] = []
    @State private var teams: [Int: Team] = [:]
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if rankings.isEmpty {
                if hasLoaded {
                    ContentUnavailableView(
                        "No ranking yet",
                        systemImage: "list.number",
                        description: Text(
                            "The commissioner posts these from FantasyPros' "
                            + "league analyzer once a week."
                        )
                    )
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                }
            } else {
                LazyVStack(spacing: Theme.Spacing.small) {
                    ForEach(rankings) { entry in
                        Card {
                            HStack(spacing: Theme.Spacing.medium) {
                                Text("\(entry.rank)")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 26, alignment: .trailing)

                                TeamLogoView(
                                    logoURL: teams[entry.teamID]?.logoURL,
                                    fallbackInitials: String(entry.teamName.prefix(2)),
                                    size: 34
                                )

                                Text(entry.teamName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)

                                Spacer(minLength: Theme.Spacing.small)

                                Text(entry.score.formatted(.number.precision(.fractionLength(0))))
                                    .font(.headline.monospacedDigit())
                            }
                        }
                    }

                    // Their number, their method — said plainly, because it
                    // will not match what the coach quotes.
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Spacing.small)
                }
            }
        }
        .task(id: environment.season) { await load() }
    }

    private var footnote: String {
        let unit = rankings.first?.unit.map { " (\($0))" } ?? ""
        let week = rankings.first?.week ?? 0
        let when = week == 0 ? "Preseason" : "After week \(week)"
        return "\(when). From FantasyPros' league analyzer\(unit), which grades "
            + "whole rosters. Coach Landry's number is this week's lineup "
            + "strength and measures something different."
    }

    private func load() async {
        defer { hasLoaded = true }
        async let published = try? await environment.content.powerRankings(
            season: environment.season)
        // Logos are decoration; losing them should not lose the table.
        async let squads = try? await environment.leagueData.teams()
        rankings = await published ?? []
        teams = Dictionary(
            uniqueKeysWithValues: (await squads ?? []).map { ($0.id, $0) })
    }
}
