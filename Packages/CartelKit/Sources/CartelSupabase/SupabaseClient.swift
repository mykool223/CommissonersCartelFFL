import Foundation
import CartelCore

public struct SupabaseConfiguration: Sendable {
    /// e.g. `https://abcdefgh.supabase.co`
    public let url: URL
    /// The *anon* (publishable) key. Safe to ship in the app — row level
    /// security is what actually protects the data. Never ship the service key.
    public let anonKey: String

    public init(url: URL, anonKey: String) {
        self.url = url
        self.anonKey = anonKey
    }
}

/// Minimal PostgREST client.
///
/// This deliberately avoids the official `supabase-swift` package: the app only
/// needs selects and two RPCs, and staying dependency-free keeps builds fast and
/// CI simple. If you later want realtime subscriptions or managed auth
/// sessions, swap this one type out for the SDK — nothing above
/// `SupabaseContentRepository` will notice.
public struct SupabaseClient: Sendable {
    private let configuration: SupabaseConfiguration
    private let transport: HTTPTransport
    /// Returns the signed-in user's JWT, or nil to fall back to the anon key.
    private let accessToken: @Sendable () async -> String?

    public init(
        configuration: SupabaseConfiguration,
        transport: HTTPTransport = URLSessionTransport(),
        accessToken: @escaping @Sendable () async -> String? = { nil }
    ) {
        self.configuration = configuration
        self.transport = transport
        self.accessToken = accessToken
    }

    /// `GET /rest/v1/{table}` with PostgREST query operators, e.g.
    /// `["season": "eq.2025", "order": "published_at.desc"]`.
    public func select<T: Decodable>(
        _ table: String,
        query: [String: String],
        as type: T.Type = T.self
    ) async throws -> T {
        var components = URLComponents(
            url: configuration.url.appending(path: "/rest/v1/\(table)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else {
            throw CartelError.notConfigured("Could not build a Supabase URL for \(table).")
        }
        return try await send(request(url: url, method: "GET"))
    }

    /// `POST /rest/v1/rpc/{function}` — calls a Postgres function.
    public func rpc<T: Decodable>(
        _ function: String,
        parameters: [String: AnyEncodable] = [:],
        as type: T.Type = T.self
    ) async throws -> T {
        let url = configuration.url.appending(path: "/rest/v1/rpc/\(function)")
        var req = request(url: url, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(parameters)
        return try await send(req)
    }

    /// `DELETE /rest/v1/{table}` with PostgREST filters.
    public func deleteRows(_ table: String, query: [String: String]) async throws {
        var components = URLComponents(
            url: configuration.url.appending(path: "/rest/v1/\(table)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else {
            throw CartelError.notConfigured("Could not build a Supabase URL for \(table).")
        }
        var request = request(url: url, method: "DELETE")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        _ = try await raw(request)
    }

    /// `PATCH /rest/v1/{table}` with PostgREST filters — updates the rows
    /// that match, and only those the caller is allowed to touch.
    public func patchRows(
        _ table: String,
        query: [String: String],
        values: [String: AnyEncodable]
    ) async throws {
        var components = URLComponents(
            url: configuration.url.appending(path: "/rest/v1/\(table)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else {
            throw CartelError.notConfigured("Could not build a Supabase URL for \(table).")
        }
        var request = request(url: url, method: "PATCH")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(values)
        _ = try await raw(request)
    }

    /// `POST /rest/v1/{table}` with `Prefer: resolution=merge-duplicates` —
    /// inserts, or updates the existing row when `onConflict` collides.
    ///
    /// Used for rows the app rewrites on every launch (a device token) rather
    /// than appends to.
    /// Upserts several rows in one request.
    ///
    /// One request rather than a loop because a set of rows can be mutually
    /// constrained — a confidence pool spends each weight once — and applying
    /// half of them can violate a constraint the whole set satisfies.
    public func upsert(
        _ table: String,
        rows: [[String: AnyEncodable]],
        onConflict: String
    ) async throws {
        var components = URLComponents(
            url: configuration.url.appending(path: "/rest/v1/\(table)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "on_conflict", value: onConflict)]
        guard let url = components?.url else {
            throw CartelError.notConfigured("Could not build a Supabase URL for \(table).")
        }
        var request = request(url: url, method: "POST")
        request.setValue("resolution=merge-duplicates,return=minimal",
                         forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(rows)
        _ = try await raw(request)
    }

    public func upsert(
        _ table: String,
        values: [String: AnyEncodable],
        onConflict: String
    ) async throws {
        var components = URLComponents(
            url: configuration.url.appending(path: "/rest/v1/\(table)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "on_conflict", value: onConflict)]
        guard let url = components?.url else {
            throw CartelError.notConfigured("Could not build a Supabase URL for \(table).")
        }
        var request = request(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "return=minimal,resolution=merge-duplicates",
            forHTTPHeaderField: "Prefer"
        )
        request.httpBody = try JSONEncoder().encode(values)
        _ = try await raw(request)
    }

    /// RPC whose return value is discarded.
    public func rpcVoid(
        _ function: String,
        parameters: [String: AnyEncodable] = [:]
    ) async throws {
        let url = configuration.url.appending(path: "/rest/v1/rpc/\(function)")
        var req = request(url: url, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONEncoder().encode(parameters)
        _ = try await raw(req)
    }

    // MARK: - Plumbing

    private func request(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func authorized(_ request: URLRequest) async -> URLRequest {
        var request = request
        let token = await accessToken() ?? configuration.anonKey
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func raw(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.send(await authorized(request))
        switch response.statusCode {
        case 200...299:
            return data
        case 401, 403:
            throw CartelError.notAuthorized
        default:
            throw CartelError.server(
                statusCode: response.statusCode,
                message: PostgRESTError.message(from: data)
            )
        }
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data = try await raw(request)
        do {
            return try JSONDecoder.supabase.decode(T.self, from: data)
        } catch {
            throw CartelError.decoding("\(T.self) didn't match the response. \(error)")
        }
    }
}

/// PostgREST returns `{"message": "...", "hint": "..."}` on failure.
private enum PostgRESTError {
    struct Payload: Decodable {
        let message: String?
        let hint: String?
        let details: String?
    }

    static func message(from data: Data) -> String? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return String(data: data.prefix(300), encoding: .utf8)
        }
        return [payload.message, payload.hint, payload.details]
            .compactMap { $0 }
            .first
    }
}

/// Type-erased `Encodable`, so RPC parameter dictionaries can mix types.
public struct AnyEncodable: Encodable, Sendable {
    private let encode: @Sendable (Encoder) throws -> Void

    public init<T: Encodable & Sendable>(_ value: T) {
        self.encode = { encoder in try value.encode(to: encoder) }
    }

    public func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}

extension JSONDecoder {
    /// Postgres `timestamptz` arrives as ISO-8601, sometimes with fractional
    /// seconds and sometimes without, and with either `Z` or a `+00:00` offset.
    /// `Date.ISO8601FormatStyle` is lenient enough to take all of those, and
    /// unlike `ISO8601DateFormatter` it is a `Sendable` value type, so it can be
    /// captured by the decoding closure without a warning.
    static let supabase: JSONDecoder = {
        let decoder = JSONDecoder()
        let style = Date.ISO8601FormatStyle()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = try? style.parse(raw) else {
                throw CartelError.decoding("Unrecognised timestamp '\(raw)'.")
            }
            return date
        }
        return decoder
    }()
}
