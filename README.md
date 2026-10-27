# NetworkKit

A typed, testable networking layer for iOS built on `URLSession` and Swift concurrency.

Endpoints describe API calls as types whose `Response` is checked by the compiler. A single
`NetworkClient` handles everything an endpoint shouldn't have to know about:

- **Auth:** bearer-token injection, with a single-flight token refresh shared by concurrent 401s.
- **Retries:** exponential backoff with jitter that honours `Retry-After`.
- **Caching:** two-level caching with a TTL and an offline fallback.
- **Interceptors (optional):** add the same extra step to every call in one place, such as a request ID or a signature.
- **Logging:** shows each call in the Xcode console with secrets like API keys and tokens hidden,
  plus optional timing for each call.
- **Errors:** one typed error surface, `NetworkError`.

- iOS 16+ / macOS 13+, Swift 6 (strict concurrency), no third-party dependencies
- Two products: `NetworkKit` (runtime) and `NetworkKitTesting` (mocks for your test targets)

> **New to NetworkKit?** Start with the step-by-step [Getting Started guide](GETTING_STARTED.md).

## Installation

In Xcode: **File ▸ Add Package Dependencies…** and enter the repository URL, or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Liji-S/NetworkKit.git", from: "0.1.0")
],
targets: [
    .target(name: "App", dependencies: ["NetworkKit"]),
    .testTarget(name: "AppTests", dependencies: ["App", "NetworkKitTesting"])
]
```

Add `NetworkKitTesting` to **test targets only**.

## Quick start

### 1. Describe the environment

```swift
import NetworkKit

extension NetworkEnvironment {
    static let production = NetworkEnvironment(
        name: "production",
        baseURL: URL(string: "https://api.example.com/v1")!,
        defaultHeaders: ["X-Api-Key": AppConfig.apiKey],
        timeout: 30,
        logLevel: .off
    )

    static let staging = NetworkEnvironment(
        name: "staging",
        baseURL: URL(string: "https://staging.api.example.com/v1")!,
        logLevel: .body
    )
}
```

### 2. Declare endpoints

Only `path` and `Response` are required. Everything else has a default: `GET`, no auth, no cache,
the environment's timeout and the client's retry policy.

```swift
struct FetchUserEndpoint: Endpoint {
    typealias Response = UserDTO
    let id: String

    var path: String { "users/\(id)" }
    var auth: AuthRequirement { .bearer }
    var cachePolicy: CachePolicy { .cacheFirst(ttl: 300) }
}

struct UpdateUserEndpoint: Endpoint {
    typealias Response = UserDTO
    let id: String
    let update: UpdateUserDTO

    var path: String { "users/\(id)" }
    var method: HTTPMethod { .patch }
    var body: RequestBody? { .json(update) }
    var auth: AuthRequirement { .bearer }
}

struct DeleteUserEndpoint: Endpoint {
    typealias Response = EmptyResponse   // 204 No Content
    let id: String
    var path: String { "users/\(id)" }
    var method: HTTPMethod { .delete }
    var auth: AuthRequirement { .bearer }
}
```

Use `Data` as the `Response` to receive the raw body, for example an image.

### 3. Build the client once, at your composition root

```swift
let client: NetworkClientProtocol = NetworkClient(
    configuration: NetworkClientConfiguration(environment: .production)
)
```

### 4. Call it from a remote data source

```swift
final class UsersRemoteDataSource: Sendable {
    private let client: NetworkClientProtocol

    init(client: NetworkClientProtocol) {
        self.client = client
    }

    func fetch(_ id: String) async throws(NetworkError) -> UserDTO {
        try await client.request(FetchUserEndpoint(id: id))
    }
}
```

`request(_:)` returns the decoded value. `response(_:)` also returns the status code, the headers
and `isFromCache`.

## Errors

Every failure is a `NetworkError`. You never see a raw `URLError` or `DecodingError`.

| Case | When |
|---|---|
| `.httpStatus(HTTPErrorResponse)` | Status outside `acceptableStatusCodes` (default `200..<300`); carries status, headers and body |
| `.decodingFailed(String)` | Body didn't match `Response`; the message includes the failing key path |
| `.noConnection` / `.timedOut` | Offline / timed out |
| `.cancelled` | The calling `Task` was cancelled |
| `.missingCredentials` | `.bearer` endpoint with no tokens or no `AuthManager` |
| `.tokenRefreshFailed(reason:sessionInvalidated:)` | Refresh failed; `sessionInvalidated == true` means sign in again |
| `.cacheMiss` | `.cacheOnly` with nothing cached |
| `.invalidURL`, `.encodingFailed`, `.invalidResponse`, `.transport`, `.underlying` | Everything else |

`NetworkError` conforms to `LocalizedError`, so `error.localizedDescription` is a user-facing message.
To decode your API's error payload:

```swift
do {
    let user = try await client.request(FetchUserEndpoint(id: "42"))
} catch NetworkError.httpStatus(let response) {
    let apiError = try? response.decodeBody(APIErrorDTO.self)
} catch {
    message = error.localizedDescription
}
```

## Authentication

```swift
let transport = URLSessionTransport()
let resolver = StaticEnvironmentResolver(.production)

let authManager = AuthManager(
    tokenStore: KeychainTokenStore(service: "com.example.app.auth"),
    refresher: EndpointTokenRefresher(
        transport: transport,
        environmentResolver: resolver,
        makeEndpoint: { refreshToken in RefreshTokenEndpoint(refreshToken: refreshToken) },
        mapResponse: { dto in
            AuthTokens(accessToken: dto.accessToken, refreshToken: dto.refreshToken, expiresIn: dto.expiresIn)
        }
    ),
    onSessionInvalidated: { await MainActor.run { appRouter.showSignIn() } }
)

let client = NetworkClient(configuration: NetworkClientConfiguration(
    environmentResolver: resolver,
    transport: transport,
    authManager: authManager
))

// After sign-in:
try await authManager.setTokens(AuthTokens(accessToken: "…", refreshToken: "…", expiresIn: 3600))

// On sign-out:
try await authManager.signOut()
await client.clearCache()
```

How it behaves:

- **Proactive refresh.** A token within `refreshLeeway` (default 60s) of `expiresAt` is refreshed before the request is sent.
- **Refresh on 401.** A `401` triggers one refresh and one replay. If several requests get a `401` at the same time, they share **one** refresh call.
- **Separate refresh call.** The refresh request bypasses the client, so it never carries the expired token and can't trigger a refresh loop.
- **When the session ends.** If the server rejects the refresh token (`400`, `401` or `403`), the tokens are cleared and `onSessionInvalidated` runs. A refresh that fails because the device is offline keeps the session.
- **Keychain storage.** `KeychainTokenStore` uses `afterFirstUnlockThisDeviceOnly` by default. Pass `accessGroup` to share tokens with app extensions.

## Caching

Only `GET` responses are cached, keyed by URL, and only after they decode successfully.

| Policy | Behaviour |
|---|---|
| `.networkOnly` (default) | Always fetch; never read or write the cache |
| `.cacheFirst(ttl:)` | Return a cached copy younger than `ttl`; otherwise fetch and cache it |
| `.cacheOnly` | Never fetch; return any cached copy, even expired, or throw `.cacheMiss` |
| `.networkFirst(ttl:)` | Always fetch and cache; **when offline**, fall back to any cached copy |

The default cache is in memory. For a cache that survives relaunches, pass a disk-backed `CacheManager`:

```swift
NetworkClientConfiguration(
    environment: .production,
    cache: CacheManager(configuration: .init(maxMemoryEntries: 200, diskCapacity: 50 * 1024 * 1024))
)
```

Give each client its own `diskDirectory`. Responses with `Cache-Control: no-store` are never cached.
Call `client.clearCache()` on sign-out.

## Retries

The default `ExponentialBackoffRetryPolicy` behaves like this:

- **Attempts:** up to 3 retries, with delays of 0.5s, 1s, 2s and so on, capped at 30s and jittered.
- **Which methods:** only idempotent ones (`GET`, `HEAD`, `PUT`, `DELETE`, `OPTIONS`).
- **Which failures:** timeouts, transient connection errors, and statuses `408`, `429`, `500`, `502`, `503` and `504`.
- **`Retry-After`** is honoured exactly. If the server asks for a longer wait than `maxDelay`, the policy gives up.
- **Time budget:** `maxElapsed` (60s) caps the total time spent retrying.
- **Cancellation is never retried.**

Override the policy per client or per endpoint:

```swift
struct PlaceOrderEndpoint: Endpoint {
    // …
    var method: HTTPMethod { .post }
    var headers: HTTPHeaders { ["Idempotency-Key": idempotencyKey] }
    var retryPolicy: (any RetryPolicy)? { ExponentialBackoffRetryPolicy(retriesNonIdempotentRequests: true) }
}
```

Use `NoRetryPolicy()` to disable retries.

## Interceptors

```swift
struct SigningInterceptor: RequestInterceptor {
    func intercept(_ request: URLRequest, context: RequestContext) async throws -> URLRequest {
        var request = request
        request.setValue(sign(request), forHTTPHeaderField: "X-Signature")
        return request
    }
}

NetworkClientConfiguration(
    environment: .production,
    requestInterceptors: [CorrelationIDInterceptor(), HeadersInterceptor(["X-App-Version": appVersion]), SigningInterceptor()],
    responseInterceptors: [AnalyticsInterceptor()]
)
```

- **Order:** request interceptors run in order. Response interceptors run in **reverse** order, on every response, including error statuses.
- **Retries:** interceptors run again on each retry and on the replay after a token refresh.
- **Correlation IDs:** `context.requestID` stays the same across retries.

## Logging and metrics

Set `logLevel` on the environment: `.off`, `.basic`, `.headers` or `.body`. The default
`OSLogNetworkLogger` writes to the unified log.

- **Redaction:** `LogRedactor` masks `Authorization`, cookies, API-key headers, query parameters such as `key` and `token`, and JSON body keys such as `password` and `refresh_token`. Bodies are capped at 4 KB.
- **Privacy:** URLs, headers and bodies are also marked `.private`.

Conform to `NetworkLogger` to forward events elsewhere.

For timing data (DNS, connect, TLS, time to first byte, transfer and protocol):

```swift
let transport = URLSessionTransport(metricsHandler: { metrics in
    Analytics.record(endpoint: metrics.url, totalMs: metrics.totalDuration * 1000)
})
```

## Environments at runtime

```swift
let resolver = SwitchableEnvironmentResolver(initial: .production)
// e.g. from a QA debug menu:
await resolver.switchTo(.staging)
```

When you switch environments, clear the cache and sign out, because both belong to the previous environment.

## Testing

`NetworkKitTesting` provides:

- **`MockNetworkClient`** to test your data sources and repositories:

  ```swift
  let client = MockNetworkClient()
  await client.stub(FetchUserEndpoint.self, with: UserDTO(id: "42", name: "Ada"))
  let dataSource = UsersRemoteDataSource(client: client)

  let user = try await dataSource.fetch("42")

  #expect(user.name == "Ada")
  #expect(await client.endpoints(of: FetchUserEndpoint.self).first?.id == "42")
  ```

- **`MockHTTPTransport`** to test the full client pipeline offline:

  ```swift
  let transport = MockHTTPTransport()
  await transport.enqueue(.status(503))
  await transport.enqueue(try .json(UserDTO(id: "42", name: "Ada")))
  let client = NetworkClient(configuration: .init(environment: .production, transport: transport))
  ```

- **`StubEndpoint<Response>`**, plus `HTTPResponse.json(_:)` and `HTTPResponse.status(_:)` helpers.

## Limitations

- Request bodies are built in memory, which suits JSON, documents and images but not very large files.
- Background `URLSession` transfers, WebSockets, streaming responses and certificate pinning aren't included.
  You can add pinning through a custom `URLSession` delegate passed to `URLSessionTransport(session:)`.
- The cache key is the URL. Responses that vary by header, such as `Accept-Language`, share an entry.

## Development

```bash
swift test                                                        # macOS
xcodebuild -scheme NetworkKit-Package -destination 'generic/platform=iOS Simulator' build
```

The Keychain tests run on macOS only. SPM test bundles on the iOS Simulator lack the Keychain entitlement.
