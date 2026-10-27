import Foundation

/// Owns the token lifecycle for `.bearer` endpoints.
///
/// - **Single-flight refresh:** however many requests discover an expired or rejected token at
///   once, exactly one refresh runs; the others await its result.
/// - **Proactive refresh:** tokens within `refreshLeeway` of `expiresAt` are refreshed before use.
/// - **Safe failure:** tokens are cleared only when the server rejects the refresh token
///   (400/401/403). A refresh that fails because the device is offline keeps the session.
/// - **Sign-out safety:** a refresh that completes after `signOut()`/`setTokens(_:)` is discarded.
public actor AuthManager {
    private let tokenStore: any TokenStore
    private let refresher: (any TokenRefresher)?
    private let refreshLeeway: TimeInterval
    private let onSessionInvalidated: (@Sendable () async -> Void)?
    private let now: @Sendable () -> Date

    private var tokens: AuthTokens?
    private var hasLoadedTokens = false
    private var refreshTask: Task<AuthTokens, any Error>?
    /// Bumped on sign-in/sign-out so an in-flight refresh can tell its result is stale.
    private var sessionGeneration = 0

    /// Creates a manager backed by `tokenStore`.
    ///
    /// Pass `nil` for `refresher` to disable refreshing; a `401` is then surfaced as-is.
    /// Tokens are refreshed `refreshLeeway` seconds before `expiresAt` to avoid a guaranteed `401`.
    /// `onSessionInvalidated` runs after the server rejects the refresh token and the stored
    /// tokens are cleared — route the user to sign-in there. `now` is injectable for tests.
    public init(
        tokenStore: any TokenStore,
        refresher: (any TokenRefresher)?,
        refreshLeeway: TimeInterval = 60,
        onSessionInvalidated: (@Sendable () async -> Void)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.tokenStore = tokenStore
        self.refresher = refresher
        self.refreshLeeway = refreshLeeway
        self.onSessionInvalidated = onSessionInvalidated
        self.now = now
    }

    // MARK: - Session

    /// Stores tokens after sign-in.
    public func setTokens(_ newTokens: AuthTokens) async throws {
        sessionGeneration += 1
        tokens = newTokens
        hasLoadedTokens = true
        try await tokenStore.save(newTokens)
    }

    /// Forgets the tokens. Also call `NetworkClient.clearCache()` so cached user data goes too.
    public func signOut() async throws {
        sessionGeneration += 1
        tokens = nil
        hasLoadedTokens = true
        try await tokenStore.clear()
    }

    public func currentTokens() async throws -> AuthTokens? {
        try await loadTokensIfNeeded()
        return tokens
    }

    // MARK: - Used by NetworkClient

    /// A usable access token, refreshing first if it is (nearly) expired.
    public func validAccessToken() async throws(NetworkError) -> String {
        try await loadTokensIfNeeded()
        guard let current = tokens else { throw .missingCredentials }
        if current.isExpired(leeway: refreshLeeway, now: now()), canRefresh(current) {
            return try await refreshTokens().accessToken
        }
        return current.accessToken
    }

    /// Called after the server answered `401` to a request sent with `rejectedAccessToken`.
    ///
    /// Returns a new access token to replay the request with, or `nil` if refreshing isn't
    /// possible (no refresher or refresh token) and the `401` should be surfaced.
    /// If another request already refreshed in the meantime, its token is returned without
    /// a second refresh.
    public func accessTokenAfterUnauthorized(rejectedAccessToken: String) async throws(NetworkError) -> String? {
        try await loadTokensIfNeeded()
        guard let current = tokens else { throw .missingCredentials }
        if current.accessToken != rejectedAccessToken {
            return current.accessToken
        }
        guard canRefresh(current) else { return nil }
        return try await refreshTokens().accessToken
    }

    // MARK: - Refresh

    private func canRefresh(_ tokens: AuthTokens) -> Bool {
        refresher != nil && tokens.refreshToken != nil
    }

    private func refreshTokens() async throws(NetworkError) -> AuthTokens {
        // Join an in-flight refresh rather than starting a second one.
        let task: Task<AuthTokens, any Error>
        if let refreshTask {
            task = refreshTask
        } else {
            let generation = sessionGeneration
            task = Task { try await self.performRefresh(generation: generation) }
            // Set before the first suspension point so concurrent callers see it.
            refreshTask = task
        }
        do {
            return try await task.value
        } catch {
            throw NetworkError(error)
        }
    }

    private func performRefresh(generation: Int) async throws(NetworkError) -> AuthTokens {
        defer { refreshTask = nil }
        guard let refresher, let current = tokens else { throw .missingCredentials }

        let refreshed: AuthTokens
        do {
            refreshed = try await refresher.refresh(using: current)
        } catch {
            let networkError = NetworkError(error)
            let rejected = Self.isRefreshTokenRejection(networkError)
            if rejected, generation == sessionGeneration {
                await invalidateSession()
            }
            throw .tokenRefreshFailed(reason: String(describing: networkError), sessionInvalidated: rejected)
        }

        // The user signed out or in while we were refreshing: don't resurrect the old session.
        guard generation == sessionGeneration else {
            guard let latest = tokens else { throw .missingCredentials }
            return latest
        }
        tokens = refreshed
        // Persisting is best-effort: the in-memory token is valid for this run either way.
        try? await tokenStore.save(refreshed)
        return refreshed
    }

    private func invalidateSession() async {
        sessionGeneration += 1
        tokens = nil
        try? await tokenStore.clear()
        await onSessionInvalidated?()
    }

    private static func isRefreshTokenRejection(_ error: NetworkError) -> Bool {
        guard let statusCode = error.statusCode else { return false }
        return [400, 401, 403].contains(statusCode)
    }

    private func loadTokensIfNeeded() async throws(NetworkError) {
        guard !hasLoadedTokens else { return }
        do {
            let loaded = try await tokenStore.load()
            // Another call may have loaded or set tokens while we awaited the store.
            if !hasLoadedTokens {
                tokens = loaded
                hasLoadedTokens = true
            }
        } catch {
            throw .underlying("Failed to load tokens: \(error)")
        }
    }
}
