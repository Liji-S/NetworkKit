import Foundation
import NetworkKit

/// A `NetworkClientProtocol` stubbed per endpoint type. Use it to test remote data sources and
/// repositories without HTTP details.
///
/// ```swift
/// let client = MockNetworkClient()
/// await client.stub(FetchUserEndpoint.self, with: UserDTO(id: "42", name: "Ada"))
/// let dataSource = UsersRemoteDataSource(client: client)
/// _ = try await dataSource.fetch("42")
/// let sent = await client.endpoints(of: FetchUserEndpoint.self)
/// #expect(sent.first?.id == "42")
/// ```
public actor MockNetworkClient: NetworkClientProtocol {
    private var handlers: [ObjectIdentifier: @Sendable (any Endpoint) async throws -> any Sendable] = [:]
    public private(set) var receivedEndpoints: [any Endpoint] = []

    public init() {}

    /// Every call to an endpoint of type `E` returns `value`.
    public func stub<E: Endpoint>(_ type: E.Type, with value: E.Response) {
        stub(type) { _ in value }
    }

    /// Every call to an endpoint of type `E` throws `error`.
    public func stub<E: Endpoint>(_ type: E.Type, error: NetworkError) {
        stub(type) { _ in throw error }
    }

    /// Computes the result from the endpoint, e.g. to return different values per ID.
    public func stub<E: Endpoint>(_ type: E.Type, handler: @escaping @Sendable (E) async throws -> E.Response) {
        handlers[ObjectIdentifier(type)] = { endpoint in
            guard let typed = endpoint as? E else {
                throw NetworkError.underlying("MockNetworkClient: endpoint type mismatch for \(E.self)")
            }
            return try await handler(typed)
        }
    }

    /// The endpoints of type `E` that were requested, in order.
    public func endpoints<E: Endpoint>(of type: E.Type) -> [E] {
        receivedEndpoints.compactMap { $0 as? E }
    }

    public func reset() {
        handlers.removeAll()
        receivedEndpoints.removeAll()
    }

    public func response<E: Endpoint>(_ endpoint: E) async throws(NetworkError) -> NetworkResponse<E.Response> {
        receivedEndpoints.append(endpoint)
        guard let handler = handlers[ObjectIdentifier(E.self)] else {
            throw .underlying("MockNetworkClient: no stub registered for \(E.self)")
        }
        do {
            guard let value = try await handler(endpoint) as? E.Response else {
                throw NetworkError.underlying("MockNetworkClient: stub for \(E.self) returned the wrong type")
            }
            return NetworkResponse(value: value, statusCode: 200)
        } catch {
            throw NetworkError(error)
        }
    }
}
