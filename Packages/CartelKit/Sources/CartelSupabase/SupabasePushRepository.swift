import Foundation
import CartelCore

/// `PushRepository` backed by Supabase.
///
/// Every call here writes only the signed-in user's own rows — row level
/// security enforces that, so a stolen anon key cannot enumerate the league's
/// device tokens or mute anyone.
public struct SupabasePushRepository: PushRepository {
    private let client: SupabaseClient
    private let userID: @Sendable () async -> UUID?

    public init(client: SupabaseClient, userID: @escaping @Sendable () async -> UUID?) {
        self.client = client
        self.userID = userID
    }

    public func registerDevice(token: String, environment: PushEnvironment) async throws {
        guard let userID = await userID() else {
            throw CartelError.notAuthorized
        }
        try await client.upsert(
            "device_tokens",
            values: [
                "token": AnyEncodable(token),
                "user_id": AnyEncodable(userID.uuidString.lowercased()),
                "environment": AnyEncodable(environment.rawValue)
            ],
            onConflict: "token"
        )
    }

    public func unregisterDevice(token: String) async throws {
        try await client.deleteRows("device_tokens", query: ["token": "eq.\(token)"])
    }

    public func notificationPreferences() async throws -> NotificationPreferences {
        guard let userID = await userID() else { return .all }
        let rows: [PreferencesRow] = try await client.select(
            "notification_preferences",
            query: ["select": "*", "user_id": "eq.\(userID.uuidString.lowercased())"]
        )
        // No row means the member has never changed anything, which means
        // everything is on.
        guard let row = rows.first else { return .all }
        return NotificationPreferences(
            messages: row.messages, news: row.news, polls: row.polls,
            activity: row.activity, lineup: row.lineup, matchups: row.matchups
        )
    }

    public func setNotificationPreferences(_ preferences: NotificationPreferences) async throws {
        guard let userID = await userID() else {
            throw CartelError.notAuthorized
        }
        try await client.upsert(
            "notification_preferences",
            values: [
                "user_id": AnyEncodable(userID.uuidString.lowercased()),
                "messages": AnyEncodable(preferences.messages),
                "news": AnyEncodable(preferences.news),
                "polls": AnyEncodable(preferences.polls),
                "activity": AnyEncodable(preferences.activity),
                "lineup": AnyEncodable(preferences.lineup),
                "matchups": AnyEncodable(preferences.matchups)
            ],
            onConflict: "user_id"
        )
    }
}

private struct PreferencesRow: Decodable {
    let messages: Bool
    let news: Bool
    let polls: Bool
    let activity: Bool
    let lineup: Bool
    let matchups: Bool

    /// Hand-written because a property default does *not* make a key
    /// optional: synthesised decoding still requires it, so a response
    /// from before the column existed would fail outright.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messages = try container.decodeIfPresent(Bool.self, forKey: .messages) ?? true
        news = try container.decodeIfPresent(Bool.self, forKey: .news) ?? true
        polls = try container.decodeIfPresent(Bool.self, forKey: .polls) ?? true
        activity = try container.decodeIfPresent(Bool.self, forKey: .activity) ?? true
        lineup = try container.decodeIfPresent(Bool.self, forKey: .lineup) ?? true
        matchups = try container.decodeIfPresent(Bool.self, forKey: .matchups) ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case messages, news, polls, activity, lineup, matchups
    }
}
