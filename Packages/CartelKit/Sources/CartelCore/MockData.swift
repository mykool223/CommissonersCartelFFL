import Foundation

/// Deterministic sample data so the whole app runs, and SwiftUI previews
/// render, before any ESPN league id or Supabase project exists.
///
/// Replace the names here with your league's once you wire up the real
/// backends — nothing else in the app depends on these values.
public enum MockData {
    /// Derived, not hardcoded. A pinned year silently empties every
    /// season-filtered screen the moment the calendar rolls over — the sample
    /// posts are still there, they just never match the season being asked for.
    public static let season = Season.current()
    public static let currentWeek = 11

    /// Stable UUIDs so previews and snapshot tests don't churn.
    public static func uuid(_ n: Int) -> UUID {
        let suffix = String(format: "%012d", n)
        return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
    }

    /// Anchor for every sample date. Captured once at launch rather than
    /// pinned, so posts read as "2 days ago" instead of drifting years stale.
    /// Stable for the lifetime of the process, which is what previews need.
    public static let referenceDate = Date()

    public static let league = League(
        id: "0000000",
        name: "Commissioners Cartel",
        season: season,
        currentWeek: currentWeek,
        regularSeasonWeeks: 14,
        teamCount: 12
    )

    public static let managers: [Manager] = [
        .init(id: "{M01}", displayName: "mykool223", firstName: "Michael", lastName: "Smith", isCommissioner: true),
        .init(id: "{M02}", displayName: "gridiron_greg", firstName: "Greg", lastName: "Alvarez"),
        .init(id: "{M03}", displayName: "dtaylor", firstName: "Dana", lastName: "Taylor"),
        .init(id: "{M04}", displayName: "punt_god", firstName: "Chris", lastName: "Nolan"),
        .init(id: "{M05}", displayName: "rjenkins", firstName: "Riley", lastName: "Jenkins"),
        .init(id: "{M06}", displayName: "the_waiver_wire", firstName: "Sam", lastName: "Okafor"),
        .init(id: "{M07}", displayName: "kdunn", firstName: "Kelly", lastName: "Dunn"),
        .init(id: "{M08}", displayName: "flexappeal", firstName: "Jordan", lastName: "Pierce"),
        .init(id: "{M09}", displayName: "amorris", firstName: "Avery", lastName: "Morris"),
        .init(id: "{M10}", displayName: "benchmob", firstName: "Casey", lastName: "Reyes"),
        .init(id: "{M11}", displayName: "tkline", firstName: "Taylor", lastName: "Kline"),
        .init(id: "{M12}", displayName: "lastpick", firstName: "Morgan", lastName: "Hale"),
    ]

    public static let teams: [Team] = [
        team(1,  "Bear Necessities",   "BEAR", "{M01}", 8, 2, 0, 1_284.6, 1_102.4, seed: 1),
        team(2,  "Trap Game",          "TRAP", "{M02}", 7, 3, 0, 1_231.8, 1_150.2, seed: 2),
        team(3,  "Kickin' It",         "KICK", "{M03}", 7, 3, 0, 1_198.0, 1_141.7, seed: 3),
        team(4,  "Fourth and Long",    "4THL", "{M04}", 6, 4, 0, 1_206.5, 1_180.9, seed: 4),
        team(5,  "Play Action Heroes", "PLAY", "{M05}", 6, 4, 0, 1_175.3, 1_168.8, seed: 5),
        team(6,  "The Audible",        "AUDI", "{M06}", 5, 5, 0, 1_162.9, 1_171.2, seed: 6),
        team(7,  "Red Zone Rebels",    "REDZ", "{M07}", 5, 5, 0, 1_144.1, 1_183.6, seed: 7),
        team(8,  "Hail Mary Inc.",     "HAIL", "{M08}", 5, 5, 0, 1_133.7, 1_190.0, seed: 8),
        team(9,  "Snap Judgment",      "SNAP", "{M09}", 4, 6, 0, 1_121.4, 1_205.3, seed: 9),
        team(10, "Blitz Brigade",      "BLTZ", "{M10}", 4, 6, 0, 1_098.2, 1_212.7, seed: 10),
        team(11, "Two Minute Warning", "2MIN", "{M11}", 3, 7, 0, 1_070.5, 1_244.1, seed: 11),
        team(12, "Waiver Wire Wonders","WIRE", "{M12}", 2, 8, 0, 1_041.9, 1_288.0, seed: 12),
    ]

    private static func team(
        _ id: Int, _ name: String, _ abbrev: String, _ owner: String,
        _ w: Int, _ l: Int, _ t: Int, _ pf: Double, _ pa: Double, seed: Int
    ) -> Team {
        Team(
            id: id,
            name: name,
            abbreviation: abbrev,
            ownerIDs: [owner],
            record: TeamRecord(wins: w, losses: l, ties: t, pointsFor: pf, pointsAgainst: pa),
            playoffSeed: seed
        )
    }

    /// Six matchups for the given week, deterministic per week.
    public static func matchups(week: Int) -> [Matchup] {
        let scores: [(Double, Double)] = [
            (121.4, 108.2), (98.6, 134.7), (117.0, 116.3),
            (142.8, 89.5), (104.2, 111.9), (127.6, 125.1),
        ]
        let complete = week < currentWeek
        return (0..<6).map { index in
            let homeID = index * 2 + 1
            let awayID = index * 2 + 2
            // Rotate the score table by week so each week looks different.
            let (homePoints, awayPoints) = scores[(index + week) % scores.count]
            return Matchup(
                id: week * 100 + index,
                week: week,
                home: MatchupSide(
                    teamID: homeID,
                    points: complete ? homePoints : 0,
                    projectedPoints: complete ? nil : homePoints
                ),
                away: MatchupSide(
                    teamID: awayID,
                    points: complete ? awayPoints : 0,
                    projectedPoints: complete ? nil : awayPoints
                ),
                isComplete: complete
            )
        }
    }

    public static let newsPosts: [NewsPost] = [
        NewsPost(
            id: uuid(1),
            title: "Week 10 Power Rankings: The Bears Are Not Slowing Down",
            body: """
            Bear Necessities moved to 8-2 and now holds the league's best point \
            differential by more than eighty points. At this stage that is less \
            a hot streak than a structural advantage.

            The interesting race is for the last two playoff spots. Four teams \
            sit at 5-5 and separated by fifty-one points of scoring, which means \
            the next three weeks decide almost everything.

            Waiver Wire Wonders remain in the basement, though to their credit \
            they have now lost four games by under six points.
            """,
            authorName: "Michael Smith",
            week: 10,
            season: season,
            publishedAt: referenceDate.addingTimeInterval(-86_400 * 2)
        ),
        NewsPost(
            id: uuid(2),
            title: "Trade Deadline Passes Quietly",
            body: """
            Two trades in the final week, neither involving a top-twelve player. \
            The Audible picked up depth at running back; Snap Judgment took a \
            flier on an injured wideout with a week 13 return date.

            Rosters are locked for the stretch run. Waivers are still open.
            """,
            authorName: "Michael Smith",
            week: 10,
            season: season,
            publishedAt: referenceDate.addingTimeInterval(-86_400 * 5)
        ),
        NewsPost(
            id: uuid(3),
            title: "Reminder: Playoff Seeding Tiebreakers",
            body: """
            Head-to-head record comes first, then total points for, then points \
            against. With four teams at 5-5 this is going to matter, so check \
            your schedule before you set a lineup you regret.
            """,
            authorName: "Michael Smith",
            season: season,
            publishedAt: referenceDate.addingTimeInterval(-86_400 * 9)
        ),
    ]

    public static func recaps(week: Int) -> [Recap] {
        [
            Recap(
                id: uuid(100 + week),
                season: season,
                week: week,
                matchupID: week * 100,
                headline: "Bears survive a scare",
                body: """
                Up thirteen with one player left, Bear Necessities watched Trap \
                Game's tight end put up nineteen in the fourth quarter. It was \
                closer than the final margin suggests.
                """,
                authorName: "Michael Smith",
                createdAt: referenceDate.addingTimeInterval(-86_400 * 3)
            ),
            Recap(
                id: uuid(200 + week),
                season: season,
                week: week,
                matchupID: week * 100 + 3,
                headline: "The blowout of the season",
                body: """
                Fifty-three points is the largest margin any team has posted \
                this year, and it came from a lineup that started two players \
                projected under eight.
                """,
                authorName: "Michael Smith",
                createdAt: referenceDate.addingTimeInterval(-86_400 * 3)
            ),
        ]
    }

    public static let externalArticles: [ExternalArticle] = [
        ExternalArticle(
            id: uuid(300),
            sourceKey: "fantasy_footballers",
            sourceName: "The Fantasy Footballers",
            title: "10 Tips and Tricks to Win Your League",
            url: URL(string: "https://www.thefantasyfootballers.com/")!,
            excerpt: "Can you smell that? There is a shift in the air. From sea breeze and sunscreen to something far more important.",
            author: "Maggie Thraen",
            publishedAt: referenceDate.addingTimeInterval(-3_600 * 5)
        ),
        ExternalArticle(
            id: uuid(301),
            sourceKey: "fantasy_footballers",
            sourceName: "The Fantasy Footballers",
            title: "Bust & Value Picks for the Season",
            url: URL(string: "https://www.thefantasyfootballers.com/")!,
            excerpt: "Bust and value picks for the fantasy football season, plus a look at where the consensus is wrong.",
            author: "The Fantasy Footballers",
            publishedAt: referenceDate.addingTimeInterval(-3_600 * 14)
        ),
    ]

    public static let polls: [Poll] = [
        Poll(
            id: uuid(10),
            question: "Who wins it all this year?",
            options: [
                PollOption(id: uuid(11), label: "Bear Necessities", voteCount: 5),
                PollOption(id: uuid(12), label: "Trap Game", voteCount: 3),
                PollOption(id: uuid(13), label: "Kickin' It", voteCount: 2),
                PollOption(id: uuid(14), label: "Literally anyone else", voteCount: 1),
            ],
            season: season,
            week: currentWeek,
            createdByName: "Michael Smith",
            createdAt: referenceDate.addingTimeInterval(-86_400),
            closesAt: referenceDate.addingTimeInterval(86_400 * 3)
        ),
        Poll(
            id: uuid(20),
            question: "Should we move to a 6-team playoff next season?",
            options: [
                PollOption(id: uuid(21), label: "Yes, six teams", voteCount: 7),
                PollOption(id: uuid(22), label: "No, keep four", voteCount: 4),
            ],
            season: season,
            createdByName: "Michael Smith",
            createdAt: referenceDate.addingTimeInterval(-86_400 * 4),
            closesAt: nil,
            myVoteOptionID: uuid(21)
        ),
        Poll(
            id: uuid(30),
            question: "Worst lineup decision of week 10?",
            options: [
                PollOption(id: uuid(31), label: "Benching a 31-point RB", voteCount: 6),
                PollOption(id: uuid(32), label: "Starting a player on bye", voteCount: 8),
                PollOption(id: uuid(33), label: "Streaming the wrong defense", voteCount: 1),
            ],
            season: season,
            week: 10,
            createdByName: "Dana Taylor",
            createdAt: referenceDate.addingTimeInterval(-86_400 * 6),
            closesAt: referenceDate.addingTimeInterval(-86_400)
        ),
    ]
}
