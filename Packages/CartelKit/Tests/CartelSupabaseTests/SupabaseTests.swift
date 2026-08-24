import Foundation
import Testing
import CartelCore
@testable import CartelSupabase

private let configuration = SupabaseConfiguration(
    url: URL(string: "https://abcdefgh.supabase.co")!,
    anonKey: "anon-key-123"
)

/// Thread-safe recorder for requests the stub transport sees.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        lock.lock(); requests.append(request); lock.unlock()
    }

    var all: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    var last: URLRequest? { all.last }
}

private func makeClient(
    responding body: String,
    statusCode: Int = 200,
    accessToken: String? = nil,
    recorder: Recorder = Recorder()
) -> (SupabaseClient, Recorder) {
    let transport = StubTransport { request in
        recorder.record(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil
        )!
        return (Data(body.utf8), response)
    }
    let client = SupabaseClient(
        configuration: configuration,
        transport: transport,
        accessToken: { accessToken }
    )
    return (client, recorder)
}

@Suite("Timestamp decoding")
struct TimestampDecodingTests {
    private struct Row: Decodable { let at: Date }

    /// Every shape Postgres `timestamptz` has been observed to produce.
    @Test(arguments: [
        "2025-11-16T17:00:00+00:00",
        "2025-11-16T17:00:00.123456+00:00",
        "2025-11-16T17:00:00Z",
        "2025-11-16T17:00:00.123Z",
        "2025-11-16T12:00:00-05:00",
    ])
    func parsesEveryPostgRESTFormat(raw: String) throws {
        let row = try JSONDecoder.supabase.decode(
            Row.self, from: Data(#"{"at":"\#(raw)"}"#.utf8)
        )
        // All five samples denote the same instant.
        #expect(abs(row.at.timeIntervalSince1970 - 1_763_312_400) < 1)
    }

    @Test("A nonsense timestamp throws rather than silently becoming 1970")
    func rejectsGarbage() {
        #expect(throws: (any Error).self) {
            try JSONDecoder.supabase.decode(Row.self, from: Data(#"{"at":"yesterday"}"#.utf8))
        }
    }
}

@Suite("PostgREST requests")
struct PostgRESTRequestTests {
    @Test("select builds the table path and passes query operators through")
    func selectURL() async throws {
        let (client, recorder) = makeClient(responding: "[]")
        let _: [String] = try await client.select(
            "news_posts",
            query: ["season": "eq.2025", "order": "published_at.desc", "limit": "10"]
        )

        let request = try #require(recorder.last)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(request.httpMethod == "GET")
        #expect(components.path == "/rest/v1/news_posts")

        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) }
        )
        #expect(items["season"] == "eq.2025")
        #expect(items["order"] == "published_at.desc")
        #expect(items["limit"] == "10")
    }

    @Test("Every request carries the apikey header")
    func sendsAPIKey() async throws {
        let (client, recorder) = makeClient(responding: "[]")
        let _: [String] = try await client.select("news_posts", query: [:])
        #expect(recorder.last?.value(forHTTPHeaderField: "apikey") == "anon-key-123")
    }

    @Test("Without a session the anon key is used as the bearer token")
    func fallsBackToAnonKey() async throws {
        let (client, recorder) = makeClient(responding: "[]")
        let _: [String] = try await client.select("news_posts", query: [:])
        #expect(recorder.last?.value(forHTTPHeaderField: "Authorization") == "Bearer anon-key-123")
    }

    @Test("A signed-in user's JWT replaces the anon key")
    func usesAccessToken() async throws {
        let (client, recorder) = makeClient(responding: "[]", accessToken: "jwt-abc")
        let _: [String] = try await client.select("news_posts", query: [:])
        #expect(recorder.last?.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-abc")
    }

    @Test("rpc posts a JSON body to /rpc/{function}")
    func rpcBody() async throws {
        let (client, recorder) = makeClient(responding: "[]")
        let _: [String] = try await client.rpc(
            "polls_with_results", parameters: ["p_season": AnyEncodable(2025)]
        )

        let request = try #require(recorder.last)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/rest/v1/rpc/polls_with_results")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let parsed = try JSONSerialization.jsonObject(with: body)
        let json = try #require(parsed as? [String: Any])
        #expect(json["p_season"] as? Int == 2025)
    }
}

@Suite("PostgREST errors")
struct PostgRESTErrorTests {
    @Test("401 and 403 become notAuthorized")
    func unauthorized() async {
        for status in [401, 403] {
            let (client, _) = makeClient(responding: "{}", statusCode: status)
            await #expect(throws: CartelError.self) {
                let _: [String] = try await client.select("news_posts", query: [:])
            }
        }
    }

    @Test("PostgREST's message field is surfaced instead of a raw body dump")
    func extractsMessage() async {
        let (client, _) = makeClient(
            responding: #"{"message":"relation \"nope\" does not exist","hint":null}"#,
            statusCode: 404
        )
        do {
            let _: [String] = try await client.select("nope", query: [:])
            Issue.record("Expected a server error")
        } catch let error as CartelError {
            guard case let .server(statusCode, message) = error else {
                Issue.record("Expected .server, got \(error)")
                return
            }
            #expect(statusCode == 404)
            #expect(message == #"relation "nope" does not exist"#)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test("A body that isn't JSON still produces a readable message")
    func nonJSONErrorBody() async {
        let (client, _) = makeClient(responding: "upstream timeout", statusCode: 504)
        do {
            let _: [String] = try await client.select("news_posts", query: [:])
            Issue.record("Expected a server error")
        } catch let error as CartelError {
            guard case let .server(_, message) = error else {
                Issue.record("Expected .server, got \(error)")
                return
            }
            #expect(message == "upstream timeout")
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }
}

@Suite("Content repository mapping")
struct ContentRepositoryTests {
    @Test("News rows map to posts, with a fallback author")
    func newsMapping() async throws {
        let json = """
        [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "title": "Week 10 Power Rankings",
            "body": "First para.\\n\\nSecond para.",
            "author_id": "00000000-0000-0000-0000-0000000000aa",
            "author_name": "Michael Smith",
            "week": 10,
            "season": 2025,
            "cover_image_url": "https://example.com/c.png",
            "published_at": "2025-11-16T17:00:00+00:00"
          },
          {
            "id": "00000000-0000-0000-0000-000000000002",
            "title": "Announcement",
            "body": "Body.",
            "author_id": null,
            "author_name": null,
            "week": null,
            "season": 2025,
            "cover_image_url": null,
            "published_at": "2025-11-10T17:00:00Z"
          }
        ]
        """
        let (client, _) = makeClient(responding: json)
        let posts = try await SupabaseContentRepository(client: client)
            .newsPosts(season: 2025, limit: 50)

        #expect(posts.count == 2)
        #expect(posts[0].title == "Week 10 Power Rankings")
        #expect(posts[0].week == 10)
        #expect(posts[0].excerpt == "First para.")
        #expect(posts[0].coverImageURL?.host() == "example.com")
        // Nullable columns must not drop the row.
        #expect(posts[1].authorName == "The Commissioner")
        #expect(posts[1].week == nil)
        #expect(posts[1].coverImageURL == nil)
    }

    @Test("polls_with_results maps into a fully-populated Poll")
    func pollMapping() async throws {
        let json = """
        [
          {
            "id": "00000000-0000-0000-0000-000000000010",
            "question": "Who wins it all?",
            "season": 2025,
            "week": 11,
            "created_by_name": "Michael Smith",
            "created_at": "2025-11-17T17:00:00+00:00",
            "closes_at": "2025-11-21T17:00:00+00:00",
            "my_vote_option_id": "00000000-0000-0000-0000-000000000012",
            "options": [
              {"id": "00000000-0000-0000-0000-000000000011", "label": "Bears", "vote_count": 5},
              {"id": "00000000-0000-0000-0000-000000000012", "label": "Trap Game", "vote_count": 3}
            ]
          }
        ]
        """
        let (client, _) = makeClient(responding: json)
        let polls = try await SupabaseContentRepository(client: client).polls(season: 2025)

        let poll = try #require(polls.first)
        #expect(poll.question == "Who wins it all?")
        #expect(poll.options.count == 2)
        #expect(poll.totalVotes == 8)
        #expect(poll.hasVoted)
        #expect(poll.myVoteOptionID == poll.options[1].id)
        #expect(poll.leadingOptions.map(\.label) == ["Bears"])
        #expect(poll.closesAt != nil)
    }

    @Test("A poll nobody has voted on decodes with no vote and no leader")
    func unvotedPoll() async throws {
        let json = """
        [
          {
            "id": "00000000-0000-0000-0000-000000000010",
            "question": "New rule?",
            "season": 2025,
            "week": null,
            "created_by_name": null,
            "created_at": "2025-11-17T17:00:00Z",
            "closes_at": null,
            "my_vote_option_id": null,
            "options": [
              {"id": "00000000-0000-0000-0000-000000000011", "label": "Yes", "vote_count": 0}
            ]
          }
        ]
        """
        let (client, _) = makeClient(responding: json)
        let poll = try #require(
            try await SupabaseContentRepository(client: client).polls(season: 2025).first
        )
        #expect(!poll.hasVoted)
        #expect(poll.totalVotes == 0)
        #expect(poll.leadingOptions.isEmpty)
        #expect(!poll.isClosed(asOf: .distantFuture), "null closes_at never closes")
        #expect(poll.createdByName == "The Commissioner")
    }

    @Test("vote calls cast_vote with both ids")
    func castsVote() async throws {
        let (client, recorder) = makeClient(responding: "")
        let pollID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let optionID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!

        try await SupabaseContentRepository(client: client).vote(pollID: pollID, optionID: optionID)

        let request = try #require(recorder.last)
        #expect(request.url?.path == "/rest/v1/rpc/cast_vote")
        #expect(request.value(forHTTPHeaderField: "Prefer") == "return=minimal")

        let httpBody = try #require(request.httpBody)
        let parsed = try JSONSerialization.jsonObject(with: httpBody)
        let json = try #require(parsed as? [String: Any])
        #expect((json["p_poll_id"] as? String)?.uppercased() == pollID.uuidString)
        #expect((json["p_option_id"] as? String)?.uppercased() == optionID.uuidString)
    }
}

@Suite("Push registration")
struct PushRepositoryTests {
    private static let user = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func makeRepository(
        responding body: String = "[]",
        statusCode: Int = 200,
        signedIn: Bool = true
    ) -> (SupabasePushRepository, Recorder) {
        let (client, recorder) = makeClient(
            responding: body,
            statusCode: statusCode,
            accessToken: signedIn ? "user-token" : nil
        )
        let repository = SupabasePushRepository(
            client: client,
            userID: { signedIn ? Self.user : nil }
        )
        return (repository, recorder)
    }

    @Test("Registering a device upserts on the token, so relaunching does not duplicate it")
    func registerUpserts() async throws {
        let (repository, recorder) = makeRepository()
        try await repository.registerDevice(token: "abc123", environment: .production)

        let request = try #require(recorder.last)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/rest/v1/device_tokens")
        // Without merge-duplicates a second launch is a primary key violation.
        let prefer = try #require(request.value(forHTTPHeaderField: "Prefer"))
        #expect(prefer.contains("resolution=merge-duplicates"))
        #expect(request.url?.query()?.contains("on_conflict=token") == true)

        let body = try #require(request.httpBody)
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["token"] as? String == "abc123")
        #expect(json["environment"] as? String == "production")
        #expect(json["user_id"] as? String == Self.user.uuidString.lowercased())
    }

    @Test("The APNs environment travels with the token")
    func environmentIsRecorded() async throws {
        let (repository, recorder) = makeRepository()
        try await repository.registerDevice(token: "abc123", environment: .sandbox)

        let body = try #require(recorder.last?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        // A sandbox token sent to the production host is rejected outright,
        // so this value is what makes the difference between working and not.
        #expect(json["environment"] as? String == "sandbox")
    }

    @Test("Registering while signed out fails rather than writing an orphan row")
    func registerRequiresSignIn() async {
        let (repository, _) = makeRepository(signedIn: false)
        await #expect(throws: CartelError.self) {
            try await repository.registerDevice(token: "abc123", environment: .production)
        }
    }

    @Test("A member with no preferences row is subscribed to everything")
    func defaultPreferences() async throws {
        let (repository, _) = makeRepository(responding: "[]")
        let preferences = try await repository.notificationPreferences()
        // Absent row means "never touched Settings", which must not read as
        // "wants silence".
        #expect(preferences == .all)
    }

    @Test("A response predating the activity column still decodes")
    func olderPreferencesShape() async throws {
        // The column was added after the first build shipped. A row without it
        // must read as "wants everything" rather than failing to decode — a
        // property default does not achieve that on its own.
        let (repository, _) = makeRepository(
            responding: #"[{"messages": false, "news": true, "polls": true}]"#
        )
        let preferences = try await repository.notificationPreferences()
        #expect(preferences.messages == false)
        #expect(preferences.activity == true)
    }

    @Test("Stored preferences are read back")
    func storedPreferences() async throws {
        let (repository, _) = makeRepository(
            responding: """
            [{"messages": false, "news": true, "polls": false, "activity": true}]
            """
        )
        let preferences = try await repository.notificationPreferences()
        #expect(preferences.messages == false)
        #expect(preferences.news == true)
        #expect(preferences.polls == false)
        #expect(preferences.isAnythingEnabled)
    }

    @Test("Turning everything off is reported as such")
    func nothingEnabled() {
        // Every kind, not merely the ones that existed when this was
        // written: the point of the check is that nothing is left on.
        #expect(!NotificationPreferences(
            messages: false, news: false, polls: false,
            activity: false, lineup: false, matchups: false
        ).isAnythingEnabled)
        // And that any single kind still counts as "something on".
        #expect(NotificationPreferences(
            messages: false, news: false, polls: false,
            activity: false, lineup: false, matchups: true
        ).isAnythingEnabled)
    }

    @Test("Unregistering deletes only this device's row")
    func unregisterIsScoped() async throws {
        let (repository, recorder) = makeRepository()
        try await repository.unregisterDevice(token: "abc123")

        let request = try #require(recorder.last)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.query()?.contains("token=eq.abc123") == true)
    }
}
