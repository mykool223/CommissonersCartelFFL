import Foundation
import CartelCore

/// Magic-link sign-in against Supabase's auth API.
///
/// Deliberately not the official SDK, matching `SupabaseClient`: the app needs
/// three calls — request a link, exchange the callback, refresh — and hand-rolling
/// them keeps the package dependency-free.
public actor SupabaseAuth {
    private let configuration: SupabaseConfiguration
    private let transport: HTTPTransport
    private let store: any SessionStore
    private let now: @Sendable () -> Date

    /// Where the emailed link sends the user back to. Must also be listed in
    /// the project's allowed redirect URLs, or Supabase refuses to send it.
    public let redirectURL: String

    private var cached: AuthSession?
    /// Guards against several screens refreshing the same expired token at once.
    private var refreshTask: Task<AuthSession?, Never>?

    public init(
        configuration: SupabaseConfiguration,
        store: any SessionStore,
        redirectURL: String = "commissionerscartel://auth-callback",
        transport: HTTPTransport = URLSessionTransport(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.store = store
        self.redirectURL = redirectURL
        self.transport = transport
        self.now = now
    }

    // MARK: - Session

    /// The stored session, refreshed if it has expired. Nil when signed out.
    public func currentSession() async -> AuthSession? {
        if cached == nil { cached = await store.load() }
        guard let session = cached else { return nil }
        guard session.isExpired(asOf: now()) else { return session }
        return await refreshed(session)
    }

    /// Access token for the API layer, or nil when signed out.
    public func accessToken() async -> String? {
        await currentSession()?.accessToken
    }

    public func signOut() async {
        cached = nil
        await store.clear()
    }

    // MARK: - Magic link

    /// Emails a sign-in link. Creates the account if the address is new.
    public func sendMagicLink(to email: String) async throws {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard address.contains("@"), address.count >= 5 else {
            throw CartelError.notConfigured("That doesn't look like an email address.")
        }

        var request = URLRequest(url: configuration.url.appending(path: "/auth/v1/otp"))
        request.httpMethod = "POST"
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            MagicLinkRequest(email: address, create_user: true)
        )

        let (data, response) = try await transport.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw CartelError.server(
                statusCode: response.statusCode,
                message: AuthErrorPayload.message(from: data)
            )
        }
    }

    /// Completes sign-in from the URL the emailed link opens.
    ///
    /// Supabase returns the tokens in the URL *fragment*, not the query, so
    /// they never reach a server — including ours.
    @discardableResult
    public func handleCallback(url: URL) async throws -> AuthSession {
        guard let fragment = url.fragment(percentEncoded: false), !fragment.isEmpty else {
            throw CartelError.notAuthorized
        }

        var values: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            values[String(parts[0])] = String(parts[1]).removingPercentEncoding ?? String(parts[1])
        }

        // Supabase reports failures in the fragment too, e.g. an expired link.
        if let error = values["error_description"] ?? values["error"] {
            throw CartelError.server(statusCode: 401, message: error.replacingOccurrences(of: "+", with: " "))
        }

        guard let accessToken = values["access_token"],
              let refreshToken = values["refresh_token"]
        else { throw CartelError.notAuthorized }

        let lifetime = values["expires_in"].flatMap(Double.init) ?? 3_600
        let session = AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: now().addingTimeInterval(lifetime),
            userID: try userID(fromAccessToken: accessToken),
            email: claims(in: accessToken)?["email"] as? String
        )

        cached = session
        await store.save(session)
        return session
    }

    /// Completes sign-in with the six-digit code from the email.
    ///
    /// The link is the nicer path, but it only works on the device holding the
    /// app — open it on a laptop and nothing happens, because the browser has
    /// no `commissionerscartel://` to hand off to. The code works from
    /// anywhere, which also makes the app reviewable without a mailbox.
    @discardableResult
    public func signIn(email: String, code: String) async throws -> AuthSession {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let token = code.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        guard token.count >= 6 else {
            throw CartelError.notConfigured("That code looks too short.")
        }

        var request = URLRequest(url: configuration.url.appending(path: "/auth/v1/verify"))
        request.httpMethod = "POST"
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            VerifyRequest(type: "email", email: address, token: token)
        )

        let (data, response) = try await transport.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw CartelError.server(
                statusCode: response.statusCode,
                message: AuthErrorPayload.message(from: data) ?? "That code didn't work."
            )
        }

        guard let payload = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw CartelError.decoding("Couldn't read the sign-in response.")
        }

        let session = AuthSession(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token ?? "",
            expiresAt: now().addingTimeInterval(Double(payload.expires_in ?? 3_600)),
            userID: try userID(fromAccessToken: payload.access_token),
            email: payload.user?.email ?? address
        )
        cached = session
        await store.save(session)
        return session
    }

    // MARK: - Refresh

    private func refreshed(_ session: AuthSession) async -> AuthSession? {
        if let refreshTask { return await refreshTask.value }

        let task = Task { () -> AuthSession? in
            var request = URLRequest(
                url: configuration.url.appending(path: "/auth/v1/token")
                    .appending(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")])
            )
            request.httpMethod = "POST"
            request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(
                RefreshRequest(refresh_token: session.refreshToken)
            )

            guard let (data, response) = try? await transport.send(request),
                  (200...299).contains(response.statusCode),
                  let payload = try? JSONDecoder().decode(TokenResponse.self, from: data),
                  let userID = try? userID(fromAccessToken: payload.access_token)
            else {
                // A refresh token that no longer works means signed out, not a
                // transient error — keeping it would retry forever.
                await signOut()
                return nil
            }

            let refreshedSession = AuthSession(
                accessToken: payload.access_token,
                refreshToken: payload.refresh_token ?? session.refreshToken,
                expiresAt: now().addingTimeInterval(Double(payload.expires_in ?? 3_600)),
                userID: userID,
                email: payload.user?.email ?? session.email
            )
            cached = refreshedSession
            await store.save(refreshedSession)
            return refreshedSession
        }

        refreshTask = task
        defer { refreshTask = nil }
        return await task.value
    }

    // MARK: - JWT

    /// Reads the `sub` claim. The signature is not checked: Supabase issued the
    /// token over TLS and verifies it again on every request, so re-checking it
    /// on device would prove nothing.
    private func userID(fromAccessToken token: String) throws -> UUID {
        guard let subject = claims(in: token)?["sub"] as? String,
              let id = UUID(uuidString: subject)
        else { throw CartelError.decoding("The sign-in token had no user id.") }
        return id
    }

    private nonisolated func claims(in token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Base64url drops padding; Data(base64Encoded:) insists on it.
        while base64.count % 4 != 0 { base64 += "=" }

        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

// MARK: - Wire types

private struct MagicLinkRequest: Encodable {
    let email: String
    let create_user: Bool
}

private struct VerifyRequest: Encodable {
    let type: String
    let email: String
    let token: String
}

private struct RefreshRequest: Encodable {
    let refresh_token: String
}

private struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int?
    let user: User?

    struct User: Decodable {
        let email: String?
    }
}

private enum AuthErrorPayload {
    struct Payload: Decodable {
        let msg: String?
        let message: String?
        let error_description: String?
    }

    static func message(from data: Data) -> String? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return String(data: data.prefix(200), encoding: .utf8)
        }
        return payload.msg ?? payload.message ?? payload.error_description
    }
}
