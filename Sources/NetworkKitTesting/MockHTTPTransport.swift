import Foundation
import NetworkKit

/// An `HTTPTransport` that never touches the network. Use it to test `NetworkClient` itself.
///
/// Queued results are returned first, in order; once the queue is empty the handler is used.
/// Every request is recorded in `requests`.
///
/// ```swift
/// let transport = MockHTTPTransport()
/// await transport.enqueue(.status(503))
/// await transport.enqueue(try .json(user))
/// ```
public actor MockHTTPTransport: HTTPTransport {
    public typealias Handler = @Sendable (URLRequest) async throws -> HTTPResponse

    private var queue: [Result<HTTPResponse, any Error>] = []
    private var handler: Handler?
    public private(set) var requests: [URLRequest] = []

    public init(handler: Handler? = nil) {
        self.handler = handler
    }

    public func setHandler(_ handler: @escaping Handler) {
        self.handler = handler
    }

    public func enqueue(_ response: HTTPResponse) {
        queue.append(.success(response))
    }

    /// Queues a failure, e.g. `URLError(.notConnectedToInternet)`.
    public func enqueue(error: any Error) {
        queue.append(.failure(error))
    }

    public var requestCount: Int { requests.count }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        if !queue.isEmpty {
            return try queue.removeFirst().get()
        }
        if let handler {
            return try await handler(request)
        }
        throw NetworkError.underlying("MockHTTPTransport: no response stubbed for \(request.url?.absoluteString ?? "<nil>")")
    }
}
