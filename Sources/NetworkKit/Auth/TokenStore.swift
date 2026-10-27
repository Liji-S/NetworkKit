import Foundation

/// Persists `AuthTokens`. Use `KeychainTokenStore` in production.
public protocol TokenStore: Sendable {
    func load() async throws -> AuthTokens?
    func save(_ tokens: AuthTokens) async throws
    func clear() async throws
}
