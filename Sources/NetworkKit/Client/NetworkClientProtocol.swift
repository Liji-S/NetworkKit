import Foundation

/// Executes typed endpoints. Depend on this protocol — not `NetworkClient` — so remote data
/// sources can be tested with `MockNetworkClient` from `NetworkKitTesting`.
public protocol NetworkClientProtocol: Sendable {
    /// Executes `endpoint` and returns the decoded value with response metadata.
    func response<E: Endpoint>(_ endpoint: E) async throws(NetworkError) -> NetworkResponse<E.Response>
}

extension NetworkClientProtocol {
    /// Executes `endpoint` and returns just the decoded value.
    public func request<E: Endpoint>(_ endpoint: E) async throws(NetworkError) -> E.Response {
        try await response(endpoint).value
    }
}
