import Foundation
import CartelCore

/// `ContentRepository` backed by Supabase.
///
/// News and recaps are straight PostgREST selects. Polls go through the
/// `polls_with_results` function instead, because assembling options, vote
/// tallies and "did I already vote" client-side would take three round trips
/// and still race. See supabase/migrations for the definitions.
public struct SupabaseContentRepository: ContentRepository {
    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func newsPosts(season: Int, limit: Int) async throws -> [NewsPost] {
        let rows: [NewsPostRow] = try await client.select(
            "news_posts",
            query: [
                "season": "eq.\(season)",
                "select": "*",
                "order": "published_at.desc",
                "limit": String(limit),
            ]
        )
        return rows.map(\.model)
    }

    public func recaps(season: Int, week: Int) async throws -> [Recap] {
        let rows: [RecapRow] = try await client.select(
            "recaps",
            query: [
                "season": "eq.\(season)",
                "week": "eq.\(week)",
                "select": "*",
                "order": "created_at.desc",
            ]
        )
        return rows.map(\.model)
    }

    public func polls(season: Int) async throws -> [Poll] {
        let rows: [PollRow] = try await client.rpc(
            "polls_with_results",
            parameters: ["p_season": AnyEncodable(season)]
        )
        return rows.map(\.model)
    }

    public func playerNews(limit: Int) async throws -> [PlayerNews] {
        let rows: [PlayerNewsRow] = try await client.select(
            "player_news",
            query: [
                "select": "*",
                "order": "published_at.desc",
                "limit": String(limit),
            ]
        )
        return rows.compactMap(\.model)
    }

    public func trophies(season: Int) async throws -> [Trophy] {
        let rows: [TrophyRow] = try await client.select(
            "trophies",
            query: ["select": "*", "season": "eq.\(season)", "order": "awarded_at.desc"]
        )
        return rows.map(\.model)
    }

    public func leagueActivity(season: Int, limit: Int) async throws -> [LeagueActivity] {
        let rows: [ActivityRow] = try await client.select(
            "league_activity",
            query: [
                "select": "*",
                "season": "eq.\(season)",
                "order": "occurred_at.desc",
                "limit": String(limit)
            ]
        )
        return rows.compactMap(\.model)
    }

    public func teamBios(season: Int) async throws -> [Int: TeamBio] {
        let rows: [TeamBioRow] = try await client.select(
            "team_bios",
            query: ["select": "*", "season": "eq.\(season)"]
        )
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.espn_team_id, $0.model) })
    }

    public func vote(pollID: UUID, optionID: UUID) async throws {
        try await client.rpcVoid(
            "cast_vote",
            parameters: [
                "p_poll_id": AnyEncodable(pollID),
                "p_option_id": AnyEncodable(optionID),
            ]
        )
    }
}

// MARK: - Row types
//
// Kept separate from the domain models so a column rename in Postgres doesn't
// ripple into the SwiftUI layer.

private struct NewsPostRow: Decodable {
    let id: UUID
    let title: String
    let body: String
    let author_id: UUID?
    let author_name: String?
    let week: Int?
    let season: Int
    let cover_image_url: String?
    let published_at: Date

    var model: NewsPost {
        NewsPost(
            id: id,
            title: title,
            body: body,
            authorID: author_id,
            authorName: author_name ?? "The Commissioner",
            week: week,
            season: season,
            coverImageURL: cover_image_url.flatMap(URL.init(string:)),
            publishedAt: published_at
        )
    }
}

private struct RecapRow: Decodable {
    let id: UUID
    let season: Int
    let week: Int
    let matchup_id: Int?
    let headline: String
    let body: String
    let author_name: String?
    let created_at: Date

    var model: Recap {
        Recap(
            id: id,
            season: season,
            week: week,
            matchupID: matchup_id,
            headline: headline,
            body: body,
            authorName: author_name ?? "The Commissioner",
            createdAt: created_at
        )
    }
}

private struct DirectMessageRow: Decodable {
    let id: UUID
    let sender_id: UUID
    let recipient_id: UUID
    let body: String
    let created_at: Date

    var model: DirectMessage {
        DirectMessage(
            id: id, senderID: sender_id, recipientID: recipient_id,
            body: body, createdAt: created_at
        )
    }
}

private struct MemberNameRow: Decodable {
    let id: UUID
    let display_name: String?
}

private struct ReactionRow: Decodable {
    let message_id: UUID
    let user_id: UUID
    let emoji: String

    var model: MessageReaction {
        MessageReaction(messageID: message_id, userID: user_id, emoji: emoji)
    }
}

private struct TrophyRow: Decodable {
    let id: UUID
    let season: Int
    let week: Int?
    let espn_team_id: Int
    let kind: String
    let title: String
    let detail: String?
    let awarded_at: Date

    var model: Trophy {
        Trophy(
            id: id, season: season, week: week, teamID: espn_team_id,
            kind: kind, title: title, detail: detail, awardedAt: awarded_at
        )
    }
}

private struct ActivityRow: Decodable {
    let id: UUID
    let kind: String
    let headline: String
    let detail: String?
    let occurred_at: Date

    /// An unrecognised kind is skipped rather than guessed at; the check
    /// constraint means it can only appear if the schema gained a case the
    /// app has not shipped support for yet.
    var model: LeagueActivity? {
        guard let kind = LeagueActivity.Kind(rawValue: kind) else { return nil }
        return LeagueActivity(
            id: id, kind: kind, headline: headline, detail: detail, occurredAt: occurred_at
        )
    }
}

private struct TeamBioRow: Decodable {
    let season: Int
    let espn_team_id: Int
    let title: String
    let bio: String

    var model: TeamBio {
        TeamBio(season: season, teamID: espn_team_id, title: title, bio: bio)
    }
}

private struct PlayerNewsRow: Decodable {
    let id: UUID
    let source_id: Int
    let source_name: String
    let player_name: String
    let player_position: String?
    let player_team: String?
    let headshot_url: String?
    let headline: String
    let blurb: String?
    let url: String
    let published_at: Date

    /// Nil when the stored URL will not parse. Dropping the row beats handing
    /// the UI an item that cannot link anywhere.
    var model: PlayerNews? {
        guard let link = URL(string: url) else { return nil }
        return PlayerNews(
            id: id,
            sourceID: source_id,
            sourceName: source_name,
            playerName: player_name,
            position: player_position,
            team: player_team,
            headshotURL: headshot_url.flatMap(URL.init(string:)),
            headline: headline,
            blurb: blurb,
            url: link,
            publishedAt: published_at
        )
    }
}

private struct PollRow: Decodable {
    let id: UUID
    let question: String
    let season: Int
    let week: Int?
    let created_by_name: String?
    let created_at: Date
    let closes_at: Date?
    let my_vote_option_id: UUID?
    let options: [OptionRow]

    struct OptionRow: Decodable {
        let id: UUID
        let label: String
        let vote_count: Int
    }

    var model: Poll {
        Poll(
            id: id,
            question: question,
            options: options.map { PollOption(id: $0.id, label: $0.label, voteCount: $0.vote_count) },
            season: season,
            week: week,
            createdByName: created_by_name ?? "The Commissioner",
            createdAt: created_at,
            closesAt: closes_at,
            myVoteOptionID: my_vote_option_id
        )
    }
}


// MARK: - League chat

extension SupabaseContentRepository: LeagueChatRepository {
    public func messages(limit: Int) async throws -> [LeagueMessage] {
        let rows: [LeagueMessageRow] = try await client.select(
            "league_messages",
            query: [
                "select": "*",
                "order": "created_at.desc",
                "limit": String(limit),
            ]
        )
        // Fetched newest-first so the limit takes the most recent, then
        // reversed so the view reads top to bottom.
        return rows.map(\.model).reversed()
    }

    public func post(_ body: String) async throws {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await client.rpcVoid("post_league_message", parameters: [
            "p_body": AnyEncodable(trimmed),
        ])
    }

    public func reactions() async throws -> [MessageReaction] {
        let rows: [ReactionRow] = try await client.select(
            "message_reactions", query: ["select": "*"]
        )
        return rows.map(\.model)
    }

    /// The row's user id is defaulted from the session in Postgres, so the
    /// client never states who it is.
    public func addReaction(messageID: UUID, emoji: String) async throws {
        try await client.upsert(
            "message_reactions",
            values: [
                "message_id": AnyEncodable(messageID.uuidString.lowercased()),
                "emoji": AnyEncodable(emoji)
            ],
            onConflict: "message_id,user_id,emoji"
        )
    }

    /// No user filter: the delete policy already restricts this to your own
    /// rows, so a filter would be decoration.
    public func removeReaction(messageID: UUID, emoji: String) async throws {
        try await client.deleteRows(
            "message_reactions",
            query: [
                "message_id": "eq.\(messageID.uuidString.lowercased())",
                "emoji": "eq.\(emoji)"
            ]
        )
    }

    public func directMessages() async throws -> [DirectMessage] {
        let rows: [DirectMessageRow] = try await client.select(
            "direct_messages", query: ["select": "*", "order": "created_at.asc"]
        )
        return rows.map(\.model)
    }

    /// The sender is defaulted from the session in Postgres, so the client
    /// never states who it is.
    public func sendDirectMessage(to recipientID: UUID, body: String) async throws {
        try await client.upsert(
            "direct_messages",
            values: [
                "recipient_id": AnyEncodable(recipientID.uuidString.lowercased()),
                "body": AnyEncodable(body)
            ],
            onConflict: "id"
        )
    }

    public func memberNames() async throws -> [UUID: String] {
        let rows: [MemberNameRow] = try await client.select(
            "profiles", query: ["select": "id,display_name"]
        )
        return Dictionary(
            uniqueKeysWithValues: rows.map { ($0.id, $0.display_name ?? "Someone") }
        )
    }

    public func deleteMessage(id: UUID) async throws {
        try await client.deleteRows("league_messages", query: ["id": "eq.\(id.uuidString)"])
    }

    public func claimESPNTeam(swid: String) async throws {
        try await client.rpcVoid("claim_espn_team", parameters: [
            "p_swid": AnyEncodable(swid),
        ])
    }

    public func createPoll(question: String, options: [String], closesAt: Date?) async throws {
        var parameters: [String: AnyEncodable] = [
            "p_question": AnyEncodable(question),
            "p_options": AnyEncodable(options),
        ]
        if let closesAt {
            parameters["p_closes_at"] = AnyEncodable(
                closesAt.formatted(.iso8601)
            )
        }
        // Discards the returned id: the list is reloaded straight afterwards.
        try await client.rpcVoid("create_poll", parameters: parameters)
    }

    public func isLeagueMember() async -> Bool {
        // RLS returns the caller's own profile and nothing else, so a row here
        // means "invited and signed in".
        let rows: [ClaimedTeamRow]? = try? await client.select(
            "profiles", query: ["select": "espn_swid", "limit": "1"]
        )
        return !(rows ?? []).isEmpty
    }

    public func claimedESPNTeam() async throws -> String? {
        let rows: [ClaimedTeamRow] = try await client.select(
            "profiles", query: ["select": "espn_swid", "limit": "1"]
        )
        return rows.first?.espn_swid
    }
}

private struct LeagueMessageRow: Decodable {
    let id: UUID
    let author_id: UUID
    let author_name: String
    let body: String
    let created_at: Date

    var model: LeagueMessage {
        LeagueMessage(
            id: id, authorID: author_id, authorName: author_name,
            body: body, createdAt: created_at
        )
    }
}

private struct ClaimedTeamRow: Decodable {
    let espn_swid: String?
}
