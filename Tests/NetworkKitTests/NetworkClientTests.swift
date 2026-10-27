import Foundation
import Testing
@testable import NetworkKit
import NetworkKitTesting

@Suite("NetworkClient")
struct NetworkClientTests {
    private let user = User(id: 1, name: "Ada")

    // MARK: - Decoding

    @Test func decodesTypedResponse() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(try .json(user))
        let client = makeClient(transport: transport)

        let response = try await client.response(StubEndpoint<User>(path: "users/1"))
        #expect(response.value == user)
        #expect(response.statusCode == 200)
        #expect(!response.isFromCache)
    }

    @Test func returnsRawDataAndEmptyResponses() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(.status(200, body: Data([0xDE, 0xAD])))
        await transport.enqueue(.status(204))
        let client = makeClient(transport: transport)

        #expect(try await client.request(StubEndpoint<Data>()) == Data([0xDE, 0xAD]))
        #expect(try await client.request(StubEndpoint<EmptyResponse>(method: .delete)) == EmptyResponse())
    }

    @Test func surfacesDecodingFailures() async {
        let transport = MockHTTPTransport()
        await transport.enqueue(.json(#"{"id": "not-a-number"}"#))
        let client = makeClient(transport: transport)

        let error = await captureNetworkError { _ = try await client.request(StubEndpoint<User>()) }
        guard case .decodingFailed(let message) = error else {
            Issue.record("Unexpected error \(String(describing: error))")
            return
        }
        #expect(message.contains("id"))
    }

    @Test func mapsRejectedStatusesToHTTPStatusError() async {
        let transport = MockHTTPTransport()
        await transport.enqueue(.json(#"{"message": "nope"}"#, statusCode: 404))
        let client = makeClient(transport: transport)

        let error = await captureNetworkError { _ = try await client.request(StubEndpoint<User>()) }
        #expect(error?.statusCode == 404)
    }

    @Test func mapsTransportErrors() async {
        let transport = MockHTTPTransport()
        await transport.enqueue(error: URLError(.notConnectedToInternet))
        let client = makeClient(transport: transport)

        let error = await captureNetworkError { _ = try await client.request(StubEndpoint<User>()) }
        #expect(error == .noConnection)
    }

    // MARK: - Authentication

    @Test func injectsBearerToken() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(try .json(user))
        let auth = AuthManager(tokenStore: InMemoryTokenStore(tokens: AuthTokens(accessToken: "t1")), refresher: nil)
        let client = makeClient(transport: transport, authManager: auth)

        _ = try await client.request(StubEndpoint<User>(auth: .bearer))
        #expect(await transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer t1")
    }

    @Test func doesNotSendTokenToUnauthenticatedEndpoints() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(try .json(user))
        let auth = AuthManager(tokenStore: InMemoryTokenStore(tokens: AuthTokens(accessToken: "t1")), refresher: nil)
        let client = makeClient(transport: transport, authManager: auth)

        _ = try await client.request(StubEndpoint<User>())
        #expect(await transport.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func bearerEndpointWithoutAuthManagerFails() async {
        let client = makeClient(transport: MockHTTPTransport())
        let error = await captureNetworkError { _ = try await client.request(StubEndpoint<User>(auth: .bearer)) }
        #expect(error == .missingCredentials)
    }

    @Test func refreshesAndReplaysOnce401() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(.status(401))
        await transport.enqueue(try .json(user))
        let counter = Counter()
        let auth = AuthManager(
            tokenStore: InMemoryTokenStore(tokens: AuthTokens(accessToken: "old", refreshToken: "r")),
            refresher: FakeRefresher(counter: counter)
        )
        let client = makeClient(transport: transport, authManager: auth)

        #expect(try await client.request(StubEndpoint<User>(auth: .bearer)) == user)
        let headers = await transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(headers == ["Bearer old", "Bearer new"])
        #expect(await counter.value == 1)
    }

    @Test func surfaces401WhenReplayIsAlsoRejected() async {
        let transport = MockHTTPTransport()
        await transport.enqueue(.status(401))
        await transport.enqueue(.status(401))
        let auth = AuthManager(
            tokenStore: InMemoryTokenStore(tokens: AuthTokens(accessToken: "old", refreshToken: "r")),
            refresher: FakeRefresher(counter: Counter())
        )
        let client = makeClient(transport: transport, authManager: auth)

        let error = await captureNetworkError { _ = try await client.request(StubEndpoint<User>(auth: .bearer)) }
        #expect(error?.statusCode == 401)
        #expect(await transport.requestCount == 2)
    }

    @Test func concurrent401sTriggerASingleRefresh() async throws {
        let user = self.user
        let transport = MockHTTPTransport { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer new"
                ? try .json(user)
                : .status(401)
        }
        let counter = Counter()
        let auth = AuthManager(
            tokenStore: InMemoryTokenStore(tokens: AuthTokens(accessToken: "old", refreshToken: "r")),
            refresher: FakeRefresher(counter: counter, delay: 0.05)
        )
        let client = makeClient(transport: transport, authManager: auth)

        let results = try await withThrowingTaskGroup(of: User.self) { group in
            for _ in 0..<10 {
                group.addTask { try await client.request(StubEndpoint<User>(auth: .bearer)) }
            }
            return try await group.reduce(into: [User]()) { $0.append($1) }
        }

        #expect(results.count == 10)
        #expect(results.allSatisfy { $0 == user })
        #expect(await counter.value == 1)
    }

    // MARK: - Retry

    @Test func retriesTransientFailuresWithBackoff() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(.status(503))
        await transport.enqueue(error: URLError(.networkConnectionLost))
        await transport.enqueue(try .json(user))
        let sleeper = RecordingSleeper()
        let client = makeClient(
            transport: transport,
            retryPolicy: ExponentialBackoffRetryPolicy(baseDelay: 0.5, jitter: 0),
            sleeper: sleeper
        )

        #expect(try await client.request(StubEndpoint<User>()) == user)
        #expect(await transport.requestCount == 3)
        #expect(sleeper.delays == [0.5, 1.0])
    }

    @Test func stopsAfterMaxRetries() async {
        let transport = MockHTTPTransport { _ in .status(503) }
        let client = makeClient(transport: transport, retryPolicy: ExponentialBackoffRetryPolicy(maxRetries: 2, jitter: 0))

        let error = await captureNetworkError { _ = try await client.request(StubEndpoint<User>()) }
        #expect(error?.statusCode == 503)
        #expect(await transport.requestCount == 3)
    }

    @Test func doesNotRetryPOST() async {
        let transport = MockHTTPTransport { _ in .status(503) }
        let client = makeClient(transport: transport, retryPolicy: ExponentialBackoffRetryPolicy(jitter: 0))

        _ = await captureNetworkError { _ = try await client.request(StubEndpoint<User>(method: .post)) }
        #expect(await transport.requestCount == 1)
    }

    @Test func endpointRetryPolicyOverridesClientDefault() async {
        let transport = MockHTTPTransport { _ in .status(503) }
        let client = makeClient(transport: transport, retryPolicy: ExponentialBackoffRetryPolicy(jitter: 0))

        _ = await captureNetworkError { _ = try await client.request(StubEndpoint<User>(retryPolicy: NoRetryPolicy())) }
        #expect(await transport.requestCount == 1)
    }

    @Test func cancellationStopsTheRequestWithoutRetrying() async throws {
        let transport = MockHTTPTransport { _ in
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return .status(200)
        }
        let client = makeClient(transport: transport, retryPolicy: ExponentialBackoffRetryPolicy(jitter: 0))

        let task = Task { try await client.request(StubEndpoint<EmptyResponse>()) }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        let result = await task.result
        #expect(throws: NetworkError.cancelled) { try result.get() }
        #expect(await transport.requestCount == 1)
    }

    // MARK: - Caching

    @Test func cacheFirstServesFreshEntriesAndRefetchesAfterTTL() async throws {
        let clock = TestClock()
        let transport = MockHTTPTransport()
        await transport.enqueue(try .json(user))
        await transport.enqueue(try .json(User(id: 1, name: "Ada Lovelace")))
        let client = makeClient(transport: transport, cache: CacheManager(configuration: .memoryOnly, now: { clock.now }))
        let endpoint = StubEndpoint<User>(path: "users/1", cachePolicy: .cacheFirst(ttl: 60))

        let first = try await client.response(endpoint)
        let second = try await client.response(endpoint)
        #expect(!first.isFromCache)
        #expect(second.isFromCache)
        #expect(second.value == user)
        #expect(await transport.requestCount == 1)

        clock.advance(by: 61)
        let third = try await client.response(endpoint)
        #expect(!third.isFromCache)
        #expect(third.value.name == "Ada Lovelace")
        #expect(await transport.requestCount == 2)
    }

    @Test func cacheOnlyNeverTouchesNetwork() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(try .json(user))
        let client = makeClient(transport: transport)

        let miss = await captureNetworkError { _ = try await client.request(StubEndpoint<User>(cachePolicy: .cacheOnly)) }
        #expect(miss == .cacheMiss)
        #expect(await transport.requestCount == 0)

        _ = try await client.request(StubEndpoint<User>(cachePolicy: .networkFirst(ttl: 60)))
        let cached = try await client.response(StubEndpoint<User>(cachePolicy: .cacheOnly))
        #expect(cached.value == user)
        #expect(cached.isFromCache)
        #expect(await transport.requestCount == 1)
    }

    @Test func networkFirstFallsBackToStaleCacheWhenOffline() async throws {
        let clock = TestClock()
        let transport = MockHTTPTransport()
        await transport.enqueue(try .json(user))
        await transport.enqueue(error: URLError(.notConnectedToInternet))
        let client = makeClient(transport: transport, cache: CacheManager(configuration: .memoryOnly, now: { clock.now }))
        let endpoint = StubEndpoint<User>(cachePolicy: .networkFirst(ttl: 10))

        _ = try await client.request(endpoint)
        clock.advance(by: 3_600) // well past the TTL
        let offline = try await client.response(endpoint)

        #expect(offline.isFromCache)
        #expect(offline.value == user)
    }

    @Test func networkFirstDoesNotHideServerErrors() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(try .json(user))
        await transport.enqueue(.status(500))
        let client = makeClient(transport: transport)
        let endpoint = StubEndpoint<User>(cachePolicy: .networkFirst(ttl: 60))

        _ = try await client.request(endpoint)
        let error = await captureNetworkError { _ = try await client.request(endpoint) }
        #expect(error?.statusCode == 500)
    }

    @Test func neverCachesNonGETRequests() async throws {
        let transport = MockHTTPTransport { _ in .json(#"{"id": 1, "name": "Ada"}"#) }
        let client = makeClient(transport: transport)
        let endpoint = StubEndpoint<User>(method: .post, cachePolicy: .cacheFirst(ttl: 60))

        _ = try await client.request(endpoint)
        _ = try await client.request(endpoint)
        #expect(await transport.requestCount == 2)
    }

    @Test func respectsNoStore() async throws {
        let transport = MockHTTPTransport { _ in .json(#"{"id": 1, "name": "Ada"}"#, headers: ["Cache-Control": "no-store"]) }
        let client = makeClient(transport: transport)
        let endpoint = StubEndpoint<User>(cachePolicy: .cacheFirst(ttl: 60))

        _ = try await client.request(endpoint)
        _ = try await client.request(endpoint)
        #expect(await transport.requestCount == 2)
    }

    @Test func doesNotCacheUndecodableResponses() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(.json(#"{"broken": true}"#))
        await transport.enqueue(try .json(user))
        let client = makeClient(transport: transport)
        let endpoint = StubEndpoint<User>(cachePolicy: .cacheFirst(ttl: 60))

        _ = await captureNetworkError { _ = try await client.request(endpoint) }
        #expect(try await client.request(endpoint) == user)
        #expect(await transport.requestCount == 2)
    }

    @Test func clearCacheRemovesEntries() async throws {
        let transport = MockHTTPTransport { _ in .json(#"{"id": 1, "name": "Ada"}"#) }
        let client = makeClient(transport: transport)
        let endpoint = StubEndpoint<User>(cachePolicy: .cacheFirst(ttl: 60))

        _ = try await client.request(endpoint)
        await client.clearCache()
        _ = try await client.request(endpoint)
        #expect(await transport.requestCount == 2)
    }

    // MARK: - Interceptors

    @Test func runsRequestInterceptorsInOrderAndResponseInterceptorsInReverse() async throws {
        let recorder = Recorder()
        let transport = MockHTTPTransport()
        await transport.enqueue(try .json(user))
        let client = makeClient(
            transport: transport,
            requestInterceptors: [OrderInterceptor(name: "A", recorder: recorder), OrderInterceptor(name: "B", recorder: recorder)],
            responseInterceptors: [OrderInterceptor(name: "A", recorder: recorder), OrderInterceptor(name: "B", recorder: recorder)]
        )

        _ = try await client.request(StubEndpoint<User>())
        #expect(await recorder.entries == ["request A", "request B", "response B", "response A"])
        #expect(await transport.requests.first?.value(forHTTPHeaderField: "X-Order") == "A,B")
    }

    @Test func correlationIDIsStableAcrossRetries() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(.status(503))
        await transport.enqueue(try .json(user))
        let client = makeClient(
            transport: transport,
            retryPolicy: ExponentialBackoffRetryPolicy(jitter: 0),
            requestInterceptors: [CorrelationIDInterceptor()]
        )

        _ = try await client.request(StubEndpoint<User>())
        let ids = await transport.requests.compactMap { $0.value(forHTTPHeaderField: "X-Request-ID") }
        #expect(ids.count == 2)
        #expect(Set(ids).count == 1)
    }

    @Test func headersInterceptorDoesNotOverrideEndpointHeaders() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(try .json(user))
        let client = makeClient(
            transport: transport,
            requestInterceptors: [HeadersInterceptor(["X-App": "interceptor", "X-Extra": "1"])]
        )

        _ = try await client.request(StubEndpoint<User>(headers: ["X-App": "endpoint"]))
        let request = await transport.requests.first
        #expect(request?.value(forHTTPHeaderField: "X-App") == "endpoint")
        #expect(request?.value(forHTTPHeaderField: "X-Extra") == "1")
    }

    @Test func throwingResponseInterceptorFailsTheRequest() async {
        let transport = MockHTTPTransport()
        await transport.enqueue(.json(#"{"id": 1, "name": "Ada"}"#))
        let client = makeClient(transport: transport, responseInterceptors: [RejectingInterceptor()])

        let error = await captureNetworkError { _ = try await client.request(StubEndpoint<User>()) }
        guard case .underlying = error else {
            Issue.record("Unexpected error \(String(describing: error))")
            return
        }
    }
}

// MARK: - Test interceptors

private struct OrderInterceptor: RequestInterceptor, ResponseInterceptor {
    let name: String
    let recorder: Recorder

    func intercept(_ request: URLRequest, context: RequestContext) async throws -> URLRequest {
        await recorder.record("request \(name)")
        var request = request
        let existing = request.value(forHTTPHeaderField: "X-Order")
        request.setValue(existing.map { "\($0),\(name)" } ?? name, forHTTPHeaderField: "X-Order")
        return request
    }

    func intercept(_ response: HTTPResponse, for request: URLRequest, context: RequestContext) async throws -> HTTPResponse {
        await recorder.record("response \(name)")
        return response
    }
}

private struct RejectingInterceptor: ResponseInterceptor {
    struct Rejected: Error {}

    func intercept(_ response: HTTPResponse, for request: URLRequest, context: RequestContext) async throws -> HTTPResponse {
        throw Rejected()
    }
}
