import Foundation

/// Sends a fully-prepared request and returns the raw response.
///
/// This is the only place bytes hit the network, which makes it the seam for testing:
/// inject `MockHTTPTransport` (from `NetworkKitTesting`) to exercise the whole client offline.
public protocol HTTPTransport: Sendable {
    /// Implementations should throw `URLError`/`CancellationError` (or `NetworkError`); the client
    /// maps them. Non-2xx statuses are *not* errors at this level.
    func send(_ request: URLRequest) async throws -> HTTPResponse
}
