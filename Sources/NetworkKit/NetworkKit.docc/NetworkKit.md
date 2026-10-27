# ``NetworkKit``

A typed, testable networking layer built on `URLSession` and Swift concurrency.

## Overview

Describe each API call as an ``Endpoint`` whose `Response` type is checked by the compiler, then
execute it with a ``NetworkClient``. The client takes care of:

- building the request against a ``NetworkEnvironment``
- bearer authentication with single-flight token refresh (``AuthManager``)
- retries (``RetryPolicy``)
- caching (``CachePolicy``)
- interceptors
- logging and metrics
- mapping every failure to ``NetworkError``

```swift
struct FetchUserEndpoint: Endpoint {
    typealias Response = UserDTO
    let id: String
    var path: String { "users/\(id)" }
    var auth: AuthRequirement { .bearer }
}

let user = try await client.request(FetchUserEndpoint(id: "42"))
```

## Topics

### Essentials

- ``Endpoint``
- ``NetworkClientProtocol``
- ``NetworkClient``
- ``NetworkClientConfiguration``
- ``NetworkResponse``
- ``NetworkError``
- ``HTTPErrorResponse``

### Describing requests

- ``HTTPMethod``
- ``HTTPHeaders``
- ``HTTPHeaderField``
- ``RequestBody``
- ``MultipartFormData``
- ``AuthRequirement``
- ``EmptyResponse``
- ``RequestBuilder``

### Environments

- ``NetworkEnvironment``
- ``EnvironmentResolver``
- ``StaticEnvironmentResolver``
- ``SwitchableEnvironmentResolver``

### Authentication

- ``AuthManager``
- ``AuthTokens``
- ``TokenStore``
- ``KeychainTokenStore``
- ``KeychainError``
- ``InMemoryTokenStore``
- ``TokenRefresher``
- ``EndpointTokenRefresher``

### Retrying

- ``RetryPolicy``
- ``RetryContext``
- ``ExponentialBackoffRetryPolicy``
- ``NoRetryPolicy``

### Caching

- ``CachePolicy``
- ``ResponseCache``
- ``CacheManager``
- ``CachedResponse``

### Interceptors

- ``RequestInterceptor``
- ``ResponseInterceptor``
- ``RequestContext``
- ``HeadersInterceptor``
- ``CorrelationIDInterceptor``

### Logging and metrics

- ``NetworkLogger``
- ``NetworkLogLevel``
- ``NetworkLogEvent``
- ``OSLogNetworkLogger``
- ``LogRedactor``
- ``NetworkMetrics``
- ``NetworkTaskMetricsDelegate``

### Transport and decoding

- ``HTTPTransport``
- ``URLSessionTransport``
- ``HTTPResponse``
- ``ResponseDecoder``
