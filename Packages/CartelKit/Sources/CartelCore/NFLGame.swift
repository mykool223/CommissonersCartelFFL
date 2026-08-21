import Foundation

/// A real NFL game, as opposed to a fantasy matchup.
public struct NFLGame: Identifiable, Hashable, Sendable {
    public enum State: String, Hashable, Sendable {
        case scheduled
        case inProgress
        case final
    }

    public struct Side: Hashable, Sendable {
        public let abbreviation: String
        public let name: String
        /// Nil before kickoff, when ESPN reports 0 for both sides.
        public let score: Int?
        /// "1-0", when ESPN supplies it.
        public let record: String?
        public let logoURL: URL?

        public init(
            abbreviation: String,
            name: String,
            score: Int? = nil,
            record: String? = nil,
            logoURL: URL? = nil
        ) {
            self.abbreviation = abbreviation
            self.name = name
            self.score = score
            self.record = record
            self.logoURL = logoURL
        }
    }

    public let id: String
    public let home: Side
    public let away: Side
    public let state: State
    /// Nil when the feed's timestamp could not be parsed. Better than
    /// inventing one: a wrong kickoff time looks perfectly plausible.
    public let startDate: Date?
    /// ESPN's own summary: "8/21 - 7:00 PM EDT", "Q3 5:42", "Final/OT".
    public let statusDetail: String
    public let period: Int?
    public let clock: String?

    public init(
        id: String,
        home: Side,
        away: Side,
        state: State,
        startDate: Date?,
        statusDetail: String,
        period: Int? = nil,
        clock: String? = nil
    ) {
        self.id = id
        self.home = home
        self.away = away
        self.state = state
        self.startDate = startDate
        self.statusDetail = statusDetail
        self.period = period
        self.clock = clock
    }

    /// Team abbreviation of the leader, or nil when level or unplayed.
    public var leadingAbbreviation: String? {
        guard let homeScore = home.score, let awayScore = away.score,
              state != .scheduled, homeScore != awayScore
        else { return nil }
        return homeScore > awayScore ? home.abbreviation : away.abbreviation
    }
}

/// One week of the NFL schedule.
public struct NFLScoreboard: Hashable, Sendable {
    public let seasonYear: Int
    public let week: Int
    public let isPreseason: Bool
    public let games: [NFLGame]

    public init(seasonYear: Int, week: Int, isPreseason: Bool, games: [NFLGame]) {
        self.seasonYear = seasonYear
        self.week = week
        self.isPreseason = isPreseason
        self.games = games
    }

    /// "Preseason Week 3" / "Week 3".
    public var weekTitle: String {
        isPreseason ? "Preseason Week \(week)" : "Week \(week)"
    }

    /// Live games first, then upcoming, then finished.
    ///
    /// A finished game is old news; one in progress is the reason anyone opened
    /// the screen.
    public var gamesInReadingOrder: [NFLGame] {
        func rank(_ state: NFLGame.State) -> Int {
            switch state {
            case .inProgress: 0
            case .scheduled: 1
            case .final: 2
            }
        }
        return games.sorted { lhs, rhs in
            if rank(lhs.state) != rank(rhs.state) { return rank(lhs.state) < rank(rhs.state) }
            // Games with no usable timestamp sort last rather than to 1970.
            switch (lhs.startDate, rhs.startDate) {
            case let (l?, r?): return l < r
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return lhs.id < rhs.id
            }
        }
    }

    public var hasLiveGames: Bool {
        games.contains { $0.state == .inProgress }
    }
}

/// Live NFL scores. Separate from `LeagueDataSource`: this is public data about
/// real games, not anything to do with a fantasy league.
public protocol NFLScoreboardSource: Sendable {
    func scoreboard() async throws -> NFLScoreboard
    /// Drops any cache so the next read goes to the network.
    func refresh() async
}

public extension NFLScoreboardSource {
    func refresh() async {}
}
