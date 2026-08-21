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
