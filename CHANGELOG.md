# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `GETTING_STARTED.md`: a step-by-step guide to installing the package and calling an API.

## [0.1.0] - 2026-10-28

### Added

- `Endpoint` protocol with typed `Response`, plus `RequestBody` (JSON, data, form, multipart) and `MultipartFormData`.
- `NetworkClient` pipeline: environment resolution, request building, interceptors, validation, decoding.
- `NetworkError`: one typed error surface for every failure.
- `AuthManager` with single-flight token refresh, `KeychainTokenStore`, `InMemoryTokenStore` and `EndpointTokenRefresher`.
- `ExponentialBackoffRetryPolicy` (jitter, `Retry-After`, idempotency-aware) and `NoRetryPolicy`.
- `CacheManager`: two-level cache (memory LRU + `URLCache` disk) with TTL, and the `CachePolicy` options.
- Request and response interceptors, with `HeadersInterceptor` and `CorrelationIDInterceptor` built in.
- `OSLogNetworkLogger` with `LogRedactor`, and `NetworkMetrics` collection.
- `NetworkKitTesting`: `MockNetworkClient`, `MockHTTPTransport`, `StubEndpoint` and response helpers.
