import SwiftUI
import WidgetKit
import CartelCore
import CartelESPN

/// This week's fixture, on the home screen.
///
/// The widget fetches its own data rather than reading a cache the app wrote:
/// a cached score goes stale silently, and a widget showing Sunday's score on
/// Tuesday is worse than one showing nothing.
struct MatchupWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MatchupWidget", provider: MatchupProvider()) { entry in
            MatchupWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Your matchup")
        .description("This week's fixture and the score.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MatchupEntry: TimelineEntry, Sendable {
    let date: Date
    let week: Int
    let mine: Side?
    let theirs: Side?
    /// Set when there is nothing to show, and why.
    let message: String?

    struct Side: Sendable {
        let name: String
        let points: Double
        let isLeading: Bool
    }

    static let placeholder = MatchupEntry(
        date: .now,
        week: 1,
        mine: Side(name: "Homicidal Pigeons", points: 96.4, isLeading: true),
        theirs: Side(name: "Dry Bones Rattle", points: 88.1, isLeading: false),
        message: nil
    )
}

/// Carries WidgetKit's completion handler across a task boundary.
///
/// Its callbacks predate Swift concurrency and are not Sendable, so passing
/// one into a `Task` is a data-race error under Swift 6. WidgetKit calls each
/// handler exactly once and does not care which thread answers, which is what
/// makes the unchecked conformance honest rather than a way of silencing the
/// compiler.
private struct CompletionBox<T>: @unchecked Sendable {
    private let handler: (T) -> Void

    init(_ handler: @escaping (T) -> Void) {
        self.handler = handler
    }

    func call(_ value: T) {
        handler(value)
    }
}

struct MatchupProvider: TimelineProvider {
    func placeholder(in context: Context) -> MatchupEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (MatchupEntry) -> Void) {
        // The gallery preview must not depend on the network.
        if context.isPreview {
            completion(.placeholder)
            return
        }
        let sink = CompletionBox(completion)
        Task { sink.call(await entry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MatchupEntry>) -> Void) {
        let sink = CompletionBox(completion)
        Task {
            // Fifteen minutes: often enough to follow a Sunday, rarely enough
            // that the system keeps honouring it.
            let next = Date.now.addingTimeInterval(15 * 60)
            sink.call(Timeline(entries: [await entry()], policy: .after(next)))
        }
    }

    private func entry() async -> MatchupEntry {
        guard let teamID = SharedStore.claimedTeamID else {
            return MatchupEntry(
                date: .now, week: 0, mine: nil, theirs: nil,
                message: "Open the Cartel and pick your team."
            )
        }

        let configuration = WidgetConfigurationValues()
        guard let client = configuration.espnClient else {
            return MatchupEntry(
                date: .now, week: 0, mine: nil, theirs: nil,
                message: "Not configured."
            )
        }

        do {
            let league = try await client.league()
            let teams = try await client.teams()
            let matchups = try await client.matchups(week: league.currentWeek)
            let names = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0.name) })

            guard let fixture = matchups.first(where: {
                $0.home.teamID == teamID || $0.away?.teamID == teamID
            }) else {
                return MatchupEntry(
                    date: .now, week: league.currentWeek, mine: nil, theirs: nil,
                    message: "No fixture this week."
                )
            }

            let isHome = fixture.home.teamID == teamID
            // A bye has no opponent, and pretending otherwise would show a
            // score against nobody.
            guard let opponent = isHome ? fixture.away : fixture.home as MatchupSide? else {
                return MatchupEntry(
                    date: .now, week: league.currentWeek, mine: nil, theirs: nil,
                    message: "Bye week."
                )
            }
            let mine = isHome ? fixture.home : (fixture.away ?? fixture.home)

            return MatchupEntry(
                date: .now,
                week: league.currentWeek,
                mine: .init(
                    name: names[mine.teamID] ?? "You",
                    points: mine.points,
                    isLeading: mine.points > opponent.points
                ),
                theirs: .init(
                    name: names[opponent.teamID] ?? "TBD",
                    points: opponent.points,
                    isLeading: opponent.points > mine.points
                ),
                message: fixture.status == .scheduled ? "Not started" : nil
            )
        } catch {
            return MatchupEntry(
                date: .now, week: 0, mine: nil, theirs: nil,
                message: "Couldn't reach the league."
            )
        }
    }
}
