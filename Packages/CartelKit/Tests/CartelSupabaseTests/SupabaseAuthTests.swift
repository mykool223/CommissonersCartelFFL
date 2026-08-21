import Foundation
import Testing
import CartelCore
@testable import CartelSupabase

private let configuration = SupabaseConfiguration(
    url: URL(string: "https://abcdefgh.supabase.co")!,
    anonKey: "anon-key-123"
)

private let userID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

/// Builds a token shaped like Supabase's: three base64url segments, with the
/// claims the app reads in the middle one. Not signed — nothing on device
/// verifies the signature, and re-checking it there would prove nothing.
private func makeJWT(sub: UUID = userID, email: String? = "commish@example.com") -> String {
    var claims: [String: Any] = ["sub": sub.uuidString]
    if let email { claims["email"] = email }
    let payload = try! JSONSerialization.data(withJSONObject: claims)
    let encoded = payload.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")   // base64url drops padding
    return "header.\(encoded).signature"
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    func record(_ r: URLRequest) { lock.lock(); requests.append(r); lock.unlock() }
    var all: [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    var last: URLRequest? { all.last }
}

private func makeAuth(
    responding body: String = "{}",
    statusCode: Int = 200,
    store: any SessionStore = InMemorySessionStore(),
    now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_000_000) },
    recorder: Recorder = Recorder()
) -> (SupabaseAuth, Recorder) {
    let transport = StubTransport { request in
        recorder.record(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil
        )!
        return (Data(body.utf8), response)
    }
    return (
        SupabaseAuth(configuration: configuration, store: store, transport: transport, now: now),
        recorder
    )
}

@Suite("Requesting a magic link")
struct MagicLinkRequestTests {
    @Test("Posts the address to the OTP endpoint and asks to create the account")
    func sendsRequest() async throws {
        let (auth, recorder) = makeAuth()
        try await auth.sendMagicLink(to: "Commish@Example.com  ")

        let request = try #require(recorder.last)
        #expect(request.url?.path == "/auth/v1/otp")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "apikey") == "anon-key-123")

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        // Trimmed and lowercased, so "Commish@Example.com " is the same account.
        #expect(json["email"] as? String == "commish@example.com")
        #expect(json["create_user"] as? Bool == true)
    }

    @Test(arguments: ["", "   ", "nope", "a@b"])
    func rejectsObviousNonAddresses(email: String) async {
        let (auth, _) = makeAuth()
        await #expect(throws: CartelError.self) { try await auth.sendMagicLink(to: email) }
    }

    @Test("A rejected request surfaces Supabase's own message")
    func surfacesServerMessage() async {
        let (auth, _) = makeAuth(
            responding: #"{"msg":"Signups not allowed for otp"}"#, statusCode: 422
        )
        do {
            try await auth.sendMagicLink(to: "commish@example.com")
            Issue.record("expected a failure")
        } catch let error as CartelError {
            guard case let .server(_, message) = error else {
                Issue.record("expected .server, got \(error)"); return
            }
            #expect(message == "Signups not allowed for otp")
        } catch {
            Issue.record("unexpected \(error)")
        }
    }
}

@Suite("Completing sign-in")
struct AuthCallbackTests {
    /// The exact fragment Supabase redirects with — captured from a real
    /// magic link, including the keys the app ignores.
    private func callbackURL(
        accessToken: String = makeJWT(),
        refresh: String = "refresh-abc",
        expiresIn: String = "3600"
    ) -> URL {
        URL(string: """
        commissionerscartel://auth-callback#access_token=\(accessToken)\
        &expires_at=1787000000&expires_in=\(expiresIn)&refresh_token=\(refresh)\
        &token_type=bearer&type=magiclink
        """)!
    }

    @Test("Tokens are read out of the fragment and stored")
    func storesSession() async throws {
        let store = InMemorySessionStore()
        let (auth, _) = makeAuth(store: store)

        let session = try await auth.handleCallback(url: callbackURL())
        #expect(session.userID == userID)
        #expect(session.email == "commish@example.com")
        #expect(session.refreshToken == "refresh-abc")
        #expect(session.expiresAt == Date(timeIntervalSince1970: 1_000_000 + 3_600))

        // Survives a relaunch.
        let persisted = try #require(await store.load())
        #expect(persisted.accessToken == session.accessToken)
    }

    @Test("The access token is what the API layer gets")
    func exposesAccessToken() async throws {
        let (auth, _) = makeAuth()
        let session = try await auth.handleCallback(url: callbackURL())
        #expect(await auth.accessToken() == session.accessToken)
    }

    /// Supabase reports a stale or reused link in the fragment rather than as
    /// an HTTP error, so this has to be read out or it looks like success.
    @Test("An expired link reports why, rather than failing silently")
    func expiredLink() async {
        let (auth, _) = makeAuth()
        let url = URL(string: """
        commissionerscartel://auth-callback#error=access_denied\
        &error_description=Email+link+is+invalid+or+has+expired
        """)!
        do {
            _ = try await auth.handleCallback(url: url)
            Issue.record("expected a failure")
        } catch let error as CartelError {
            guard case let .server(_, message) = error else {
                Issue.record("expected .server, got \(error)"); return
            }
            #expect(message == "Email link is invalid or has expired")
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test(arguments: [
        "commissionerscartel://auth-callback",
        "commissionerscartel://auth-callback#token_type=bearer",
        "commissionerscartel://auth-callback#access_token=notajwt&refresh_token=r",
    ])
    func rejectsUnusableCallbacks(raw: String) async {
        let (auth, _) = makeAuth()
        await #expect(throws: CartelError.self) {
            _ = try await auth.handleCallback(url: URL(string: raw)!)
        }
    }

    @Test("Signing out forgets the session")
    func signOut() async throws {
        let store = InMemorySessionStore()
        let (auth, _) = makeAuth(store: store)
        _ = try await auth.handleCallback(url: callbackURL())

        await auth.signOut()
        #expect(await auth.accessToken() == nil)
        #expect(await store.load() == nil)
    }
}

@Suite("Refreshing a session")
struct AuthRefreshTests {
    private func expiredSession() -> AuthSession {
        AuthSession(
            accessToken: makeJWT(),
            refreshToken: "refresh-old",
            expiresAt: Date(timeIntervalSince1970: 900_000),   // already past
            userID: userID,
            email: "commish@example.com"
        )
    }

    @Test("An expired session is refreshed before it is handed out")
    func refreshesExpired() async throws {
        let store = InMemorySessionStore(session: expiredSession())
        let body = """
        {"access_token":"\(makeJWT())","refresh_token":"refresh-new","expires_in":3600}
        """
        let (auth, recorder) = makeAuth(responding: body, store: store)

        let session = try #require(await auth.currentSession())
        #expect(session.refreshToken == "refresh-new")
        #expect(!session.isExpired(asOf: Date(timeIntervalSince1970: 1_000_000)))

        let request = try #require(recorder.last)
        #expect(request.url?.path == "/auth/v1/token")
        #expect(request.url?.query?.contains("grant_type=refresh_token") == true)
    }

    /// A token about to expire mid-flight is as useless as one already dead.
    @Test("A session expiring within the minute counts as expired")
    func refreshesNearlyExpired() {
        let session = AuthSession(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date(timeIntervalSince1970: 1_000_030),
            userID: userID
        )
        #expect(session.isExpired(asOf: Date(timeIntervalSince1970: 1_000_000)))
    }

    @Test("A valid session is handed back without a network call")
    func skipsRefreshWhenValid() async throws {
        let session = AuthSession(
            accessToken: makeJWT(), refreshToken: "r",
            expiresAt: Date(timeIntervalSince1970: 2_000_000),
            userID: userID
        )
        let (auth, recorder) = makeAuth(store: InMemorySessionStore(session: session))
        _ = await auth.currentSession()
        #expect(recorder.all.isEmpty)
    }

    /// A refresh token the server rejects is not a transient failure; keeping
    /// it would retry forever on every screen.
    @Test("A rejected refresh signs the user out")
    func rejectedRefreshSignsOut() async {
        let store = InMemorySessionStore(session: expiredSession())
        let (auth, _) = makeAuth(
            responding: #"{"error":"invalid_grant"}"#, statusCode: 400, store: store
        )
        #expect(await auth.currentSession() == nil)
        #expect(await store.load() == nil)
    }

    @Test("Concurrent callers share one refresh")
    func coalescesRefresh() async throws {
        let body = """
        {"access_token":"\(makeJWT())","refresh_token":"refresh-new","expires_in":3600}
        """
        let (auth, recorder) = makeAuth(
            responding: body, store: InMemorySessionStore(session: expiredSession())
        )
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { _ = await auth.currentSession() } }
        }
        #expect(recorder.all.count == 1)
    }
}
