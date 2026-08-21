import Foundation
import CartelCore

/// Wire types for ESPN's public scoreboard endpoint.
///
/// Undocumented like the fantasy API, so everything below the top level is
/// optional and mapping happens in one place.
struct ESPNScoreboardResponse: Decodable {
    let season: Season?
    let week: Week?
    let events: [Event]?

    struct Season: Decodable {
        let year: Int?
        /// 1 preseason, 2 regular, 3 postseason.
        let type: Int?
    }

    struct Week: Decodable {
        let number: Int?
    }

    struct Event: Decodable {
        let id: String
        let date: String?
        let competitions: [Competition]?
    }

    struct Competition: Decodable {
        let status: Status?
        let competitors: [Competitor]?

        struct Status: Decodable {
            let period: Int?
            let displayClock: String?
            let type: StatusType?

            struct StatusType: Decodable {
                /// "pre", "in", "post".
                let state: String?
                let completed: Bool?
                let shortDetail: String?
                let detail: String?
            }
        }

        struct Competitor: Decodable {
            let homeAway: String?
            /// Comes back as a string, not a number.
            let score: String?
            let team: Team?
            let records: [Record]?

            struct Team: Decodable {
                let abbreviation: String?
                let displayName: String?
                let shortDisplayName: String?
                let logo: String?
            }

            struct Record: Decodable {
                let summary: String?
            }
        }
    }
}

enum ESPNScoreboardMapper {
    static func scoreboard(from dto: ESPNScoreboardResponse) -> NFLScoreboard {
        NFLScoreboard(
            seasonYear: dto.season?.year ?? Season.current(),
            week: dto.week?.number ?? 1,
            isPreseason: dto.season?.type == 1,
            games: (dto.events ?? []).compactMap(game(from:))
        )
    }

    static func game(from event: ESPNScoreboardResponse.Event) -> NFLGame? {
        guard let competition = event.competitions?.first,
              let competitors = competition.competitors,
              let home = competitors.first(where: { $0.homeAway == "home" }),
              let away = competitors.first(where: { $0.homeAway == "away" })
        else { return nil }

        let status = competition.status
        let state = state(from: status?.type)

        return NFLGame(
            id: event.id,
            home: side(from: home, state: state),
            away: side(from: away, state: state),
            state: state,
            // ESPN sends "2026-08-21T23:00Z" — no seconds — which the stock
            // ISO-8601 parser rejects outright.
            startDate: event.date.flatMap(FlexibleISO8601.date(from:)),
            statusDetail: status?.type?.shortDetail ?? status?.type?.detail ?? "",
            // Zeroes before kickoff mean "no period yet", not "period zero".
            period: (status?.period ?? 0) > 0 ? status?.period : nil,
            clock: state == .inProgress ? status?.displayClock : nil
        )
    }

    private static func state(
        from type: ESPNScoreboardResponse.Competition.Status.StatusType?
    ) -> NFLGame.State {
        if type?.completed == true { return .final }
        switch type?.state {
        case "in": return .inProgress
        case "post": return .final
        default: return .scheduled
        }
    }

    private static func side(
        from competitor: ESPNScoreboardResponse.Competition.Competitor,
        state: NFLGame.State
    ) -> NFLGame.Side {
        NFLGame.Side(
            abbreviation: competitor.team?.abbreviation ?? "?",
            name: competitor.team?.shortDisplayName
                ?? competitor.team?.displayName
                ?? "Unknown",
            // ESPN reports "0" for both sides before kickoff, which would
            // render as a 0-0 scoreline for a game that has not started.
            score: state == .scheduled ? nil : competitor.score.flatMap(Int.init),
            record: competitor.records?.first?.summary,
            logoURL: competitor.team?.logo.flatMap(URL.init(string:))
        )
    }
}
