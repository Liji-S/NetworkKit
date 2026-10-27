import Foundation

/// Keeps tokens in memory only — they are lost when the app exits.
/// Useful for tests, previews and apps that deliberately don't persist sessions.
public actor InMemoryTokenStore: TokenStore {
    private var tokens: AuthTokens?

    public init(tokens: AuthTokens? = nil) {
        self.tokens = tokens
    }

    public func load() async throws -> AuthTokens? {
        tokens
    }

    public func save(_ tokens: AuthTokens) async throws {
        self.tokens = tokens
    }

    public func clear() async throws {
        tokens = nil
    }
}
