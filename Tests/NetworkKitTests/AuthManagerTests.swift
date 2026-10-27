import Foundation
import Testing
import NetworkKit

@Suite("AuthManager")
struct AuthManagerTests {
    private let initialTokens = AuthTokens(accessToken: "old", refreshToken: "refresh-1")

    @Test func returnsStoredAccessToken() async throws {
        let manager = AuthManager(tokenStore: InMemoryTokenStore(tokens: initialTokens), refresher: nil)
        #expect(try await manager.validAccessToken() == "old")
    }

    @Test func throwsMissingCredentialsWithoutTokens() async {
        let manager = AuthManager(tokenStore: InMemoryTokenStore(), refresher: nil)
        let error = await captureNetworkError { _ = try await manager.validAccessToken() }
        #expect(error == .missingCredentials)
    }

    @Test func refreshesProactivelyWhenTokenIsAboutToExpire() async throws {
        let clock = TestClock()
        let counter = Counter()
        let store = InMemoryTokenStore(tokens: AuthTokens(
            accessToken: "old",
            refreshToken: "refresh-1",
            expiresAt: clock.now.addingTimeInterval(30)
        ))
        let manager = AuthManager(
            tokenStore: store,
            refresher: FakeRefresher(counter: counter),
            refreshLeeway: 60,
            now: { clock.now }
        )

        #expect(try await manager.validAccessToken() == "new")
        #expect(await counter.value == 1)
        #expect(try await store.load()?.accessToken == "new")
    }

    @Test func concurrentUnauthorizedCallsShareOneRefresh() async throws {
        let counter = Counter()
        let manager = AuthManager(
            tokenStore: InMemoryTokenStore(tokens: initialTokens),
            refresher: FakeRefresher(counter: counter, delay: 0.05)
        )

        let tokens = try await withThrowingTaskGroup(of: String?.self) { group in
            for _ in 0..<20 {
                group.addTask { try await manager.accessTokenAfterUnauthorized(rejectedAccessToken: "old") }
            }
            return try await group.reduce(into: [String?]()) { $0.append($1) }
        }

        #expect(tokens.count == 20)
        #expect(tokens.allSatisfy { $0 == "new" })
        #expect(await counter.value == 1)
    }

    @Test func doesNotRefreshAgainForAnAlreadyReplacedToken() async throws {
        let counter = Counter()
        let manager = AuthManager(tokenStore: InMemoryTokenStore(tokens: initialTokens), refresher: FakeRefresher(counter: counter))

        #expect(try await manager.accessTokenAfterUnauthorized(rejectedAccessToken: "old") == "new")
        // A slow request that was sent with "old" comes back 401 after the refresh finished.
        #expect(try await manager.accessTokenAfterUnauthorized(rejectedAccessToken: "old") == "new")
        #expect(await counter.value == 1)
    }

    @Test func returnsNilWhenRefreshIsNotPossible() async throws {
        let manager = AuthManager(tokenStore: InMemoryTokenStore(tokens: initialTokens), refresher: nil)
        #expect(try await manager.accessTokenAfterUnauthorized(rejectedAccessToken: "old") == nil)

        let noRefreshToken = AuthManager(
            tokenStore: InMemoryTokenStore(tokens: AuthTokens(accessToken: "old")),
            refresher: FakeRefresher(counter: Counter())
        )
        #expect(try await noRefreshToken.accessTokenAfterUnauthorized(rejectedAccessToken: "old") == nil)
    }

    @Test func rejectedRefreshTokenInvalidatesSession() async throws {
        let store = InMemoryTokenStore(tokens: initialTokens)
        let invalidations = Counter()
        let refresher = FakeRefresher(counter: Counter()) { _ in
            throw NetworkError.httpStatus(HTTPErrorResponse(statusCode: 401))
        }
        let manager = AuthManager(
            tokenStore: store,
            refresher: refresher,
            onSessionInvalidated: { await invalidations.increment() }
        )

        let error = await captureNetworkError { _ = try await manager.accessTokenAfterUnauthorized(rejectedAccessToken: "old") }

        guard case .tokenRefreshFailed(_, let sessionInvalidated) = error else {
            Issue.record("Unexpected error \(String(describing: error))")
            return
        }
        #expect(sessionInvalidated)
        #expect(try await store.load() == nil)
        #expect(try await manager.currentTokens() == nil)
        #expect(await invalidations.value == 1)
    }

    @Test func offlineRefreshFailureKeepsSession() async throws {
        let store = InMemoryTokenStore(tokens: initialTokens)
        let refresher = FakeRefresher(counter: Counter()) { _ in throw URLError(.notConnectedToInternet) }
        let manager = AuthManager(tokenStore: store, refresher: refresher)

        let error = await captureNetworkError { _ = try await manager.accessTokenAfterUnauthorized(rejectedAccessToken: "old") }

        guard case .tokenRefreshFailed(_, let sessionInvalidated) = error else {
            Issue.record("Unexpected error \(String(describing: error))")
            return
        }
        #expect(!sessionInvalidated)
        #expect(try await store.load() == initialTokens)
    }

    @Test func signOutDuringRefreshDiscardsRefreshedTokens() async throws {
        let store = InMemoryTokenStore(tokens: initialTokens)
        let manager = AuthManager(tokenStore: store, refresher: FakeRefresher(counter: Counter(), delay: 0.2))

        let pending = Task { try await manager.accessTokenAfterUnauthorized(rejectedAccessToken: "old") }
        try await Task.sleep(nanoseconds: 50_000_000)
        try await manager.signOut()

        let result = await pending.result
        #expect(throws: NetworkError.missingCredentials) { try result.get() }
        #expect(try await manager.currentTokens() == nil)
        #expect(try await store.load() == nil)
    }

    @Test func setTokensReplacesSession() async throws {
        let store = InMemoryTokenStore()
        let manager = AuthManager(tokenStore: store, refresher: nil)
        try await manager.setTokens(initialTokens)
        #expect(try await manager.validAccessToken() == "old")
        #expect(try await store.load() == initialTokens)
    }

    @Test func tokenExpiryHonoursLeeway() {
        let now = Date()
        let tokens = AuthTokens(accessToken: "a", expiresIn: 30, now: now)
        #expect(!tokens.isExpired(leeway: 0, now: now))
        #expect(tokens.isExpired(leeway: 60, now: now))
        #expect(!AuthTokens(accessToken: "a").isExpired(leeway: 1_000, now: now))
    }
}
