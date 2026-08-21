import Foundation

/// Seam between the API clients and `URLSession`.
///
/// Both `ESPNClient` and `SupabaseClient` talk to this instead of URLSession
/// directly, so tests can replay saved JSON fixtures without a network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CartelError.transport("Response was not HTTP.")
            }
            return (data, http)
        } catch let error as CartelError {
            throw error
        } catch {
            throw CartelError.transport(error.localizedDescription)
        }
    }
}

/// Replays canned responses. Test-only, but shipped in the library so test
/// targets in either module can use it.
public struct StubTransport: HTTPTransport {
    private let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    public init(handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    /// Always returns `data` with the given status code.
    public init(data: Data, statusCode: Int = 200) {
        self.init { request in
            let url = request.url ?? URL(string: "https://example.invalid")!
            let response = HTTPURLResponse(
                url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil
            )!
            return (data, response)
        }
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try handler(request)
    }
}
