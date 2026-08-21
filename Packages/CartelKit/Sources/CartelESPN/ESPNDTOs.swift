import Foundation
import CartelCore

/// Wire types for ESPN's fantasy v3 payload.
///
/// This endpoint is undocumented and ESPN changes it without notice, so almost
/// every field is optional and mapping happens in one place (`ESPNMapper`).
/// When a screen suddenly goes empty, this file is where to look first.
struct ESPNLeagueResponse: Decodable {
    let id: Int
    let seasonId: Int?
    let status: Status?
    let settings: Settings?
    let teams: [TeamDTO]?
    let members: [MemberDTO]?
    let schedule: [ScheduleItemDTO]?

    struct Status: Decodable {
        let currentMatchupPeriod: Int?
        let latestScoringPeriod: Int?
        let finalScoringPeriod: Int?
    }

    struct Settings: Decodable {
        let name: String?
        let scheduleSettings: ScheduleSettings?

        struct ScheduleSettings: Decodable {
            let matchupPeriodCount: Int?
        }
    }

    struct MemberDTO: Decodable {
        let id: String
        let displayName: String?
        let firstName: String?
        let lastName: String?
        let isLeagueManager: Bool?
    }

    struct TeamDTO: Decodable {
        let id: Int
        let abbrev: String?
        /// Seasons from ~2023 onward return a single `name`.
        let name: String?
        /// Older seasons split the name into `location` + `nickname`.
        let location: String?
        let nickname: String?
        let logo: String?
        let owners: [String]?
        let primaryOwner: String?
        let playoffSeed: Int?
        let record: RecordDTO?

        struct RecordDTO: Decodable {
            let overall: Overall?

            struct Overall: Decodable {
                let wins: Int?
                let losses: Int?
                let ties: Int?
                let pointsFor: Double?
                let pointsAgainst: Double?
            }
        }
    }

    struct ScheduleItemDTO: Decodable {
        let id: Int?
        let matchupPeriodId: Int?
        /// "HOME", "AWAY", "TIE" or "UNDECIDED".
        let winner: String?
        let home: SideDTO?
        /// Absent for bye matchups in odd-sized leagues.
        let away: SideDTO?

        struct SideDTO: Decodable {
            let teamId: Int
            let totalPoints: Double?
            let totalProjectedPointsLive: Double?
        }
    }
}
