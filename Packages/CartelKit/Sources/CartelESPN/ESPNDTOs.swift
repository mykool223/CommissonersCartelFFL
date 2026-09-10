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
            let divisions: [DivisionDTO]?
        }

        struct DivisionDTO: Decodable {
            let id: Int
            let name: String?
            let size: Int?
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
        let divisionId: Int?
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
            /// Zero until ESPN settles the matchup period, so this is the
            /// final score and nothing else. During play it reads 0.0 no
            /// matter what is happening on the field.
            let totalPoints: Double?
            /// What the side has scored so far. This is the number people mean
            /// when they ask what the score is.
            let totalPointsLive: Double?
            let totalProjectedPointsLive: Double?
            /// Present only when the payload was fetched with `mBoxscore`.
            /// Without that view the entries arrive stripped of names, which
            /// is why the app asks for it.
            ///
            /// This is the roster as it stands now, so it is the complete and
            /// current one while a week is being played — and the wrong one
            /// for a week that finished, where it would show today's lineup.
            let rosterForCurrentScoringPeriod: RosterDTO?
            /// The roster as it was for this matchup period. Correct for a
            /// week that has been settled, but only partly filled in while one
            /// is still being played.
            let rosterForMatchupPeriod: RosterDTO?

            struct RosterDTO: Decodable {
                let entries: [EntryDTO]?

                struct EntryDTO: Decodable {
                    /// ESPN's slot numbering: 20 is the bench, 21 injured
                    /// reserve, 23 the flex. Translated in ESPNMapper.
                    let lineupSlotId: Int?
                    let playerPoolEntry: PlayerPoolEntryDTO?

                    struct PlayerPoolEntryDTO: Decodable {
                        let id: Int?
                        /// What this player has scored this week.
                        let appliedStatTotal: Double?
                        let player: PlayerDTO?

                        struct PlayerDTO: Decodable {
                            let id: Int?
                            let fullName: String?
                            let defaultPositionId: Int?
                        }
                    }
                }
            }
        }
    }
}
