import Foundation

/// A signed-in Supabase session.
public struct AuthSession: Hashable, Sendable, Codable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let userID: UUID
    public let email: String?

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        userID: UUID,
        email: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID
        self.email = email
    }

    /// Treated as expired a minute early, so a request never goes out with a
    /// token that dies in flight.
    public func isExpired(asOf now: Date = Date()) -> Bool {
        now.addingTimeInterval(60) >= expiresAt
    }
}

/// Where a session is kept between launches.
///
/// Defined here so `SupabaseAuth` does not need to know about the Keychain,
/// which lives in the app target.
public protocol SessionStore: Sendable {
    func load() async -> AuthSession?
    func save(_ session: AuthSession) async
    func clear() async
}

/// Keeps a session only for the lifetime of the process. Useful in tests and
/// previews; the app uses a Keychain-backed store.
public actor InMemorySessionStore: SessionStore {
    private var session: AuthSession?

    public init(session: AuthSession? = nil) {
        self.session = session
    }

    public func load() async -> AuthSession? { session }
    public func save(_ session: AuthSession) async { self.session = session }
    public func clear() async { session = nil }
}
