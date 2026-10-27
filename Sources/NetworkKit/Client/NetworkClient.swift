import Foundation

/// The production `NetworkClientProtocol`.
///
/// For each `response(_:)` call:
/// 1. Resolve the environment and build the `URLRequest`.
/// 2. Read the cache according to the endpoint's `CachePolicy` (`GET` only).
/// 3. Execute with retries. Each attempt injects the bearer token, runs request interceptors,
///    sends, runs response interceptors and logs; a `401` triggers one token refresh and replay.
/// 4. Map non-accepted statuses and transport failures to `NetworkError`.
/// 5. Decode into `Endpoint.Response`, then write the cache (only after a successful decode).
/// 6. On connectivity failure with `.networkFirst`, fall back to a cached response.
public final class NetworkClient: NetworkClientProtocol {
    private let configuration: NetworkClientConfiguration
    private let builder: RequestBuilder
    private let decoder: ResponseDecoder
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    public convenience init(configuration: NetworkClientConfiguration) {
        self.init(configuration: configuration) { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    }

    /// Lets tests replace the retry back-off sleep.
    init(configuration: NetworkClientConfiguration, sleep: @escaping @Sendable (TimeInterval) async throws -> Void) {
        self.configuration = configuration
        self.builder = RequestBuilder(encoder: configuration.encoder)
        self.decoder = ResponseDecoder(decoder: configuration.decoder)
        self.sleep = sleep
    }

    public func response<E: Endpoint>(_ endpoint: E) async throws(NetworkError) -> NetworkResponse<E.Response> {
        do {
            return try await perform(endpoint)
        } catch {
            throw NetworkError(error)
        }
    }

    /// Removes every cached response. Call on sign-out and when switching environments.
    public func clearCache() async {
        await configuration.cache?.removeAll()
    }

    // MARK: - Pipeline

    private func perform<E: Endpoint>(_ endpoint: E) async throws -> NetworkResponse<E.Response> {
        try Task.checkCancellation()
        let environment = await configuration.environmentResolver.currentEnvironment()
        let context = RequestContext(endpointName: endpoint.name, environmentName: environment.name)
        let request = try builder.makeRequest(for: endpoint, environment: environment)

        let cachePolicy = endpoint.method == .get ? endpoint.cachePolicy : .networkOnly
        let cacheKey = request.url?.absoluteString
        let cache = cachePolicy == .networkOnly ? nil : configuration.cache

        if cachePolicy == .cacheOnly, cache == nil {
            throw NetworkError.cacheMiss
        }

        // Cache read.
        if let cache, let cacheKey {
            switch cachePolicy {
            case .cacheOnly:
                guard let entry = await cache.cachedResponse(for: cacheKey) else { throw NetworkError.cacheMiss }
                log(.cacheHit(url: request.url, isExpired: entry.isExpired, context: context), environment)
                let value = try decoder.decode(E.Response.self, from: entry.response)
                return NetworkResponse(value: value, response: entry.response, isFromCache: true)
            case .cacheFirst:
                // An undecodable cached entry (e.g. after a model change) falls through to the network.
                if let entry = await cache.cachedResponse(for: cacheKey), !entry.isExpired,
                   let value = try? decoder.decode(E.Response.self, from: entry.response) {
                    log(.cacheHit(url: request.url, isExpired: false, context: context), environment)
                    return NetworkResponse(value: value, response: entry.response, isFromCache: true)
                }
            case .networkOnly, .networkFirst:
                break
            }
        }

        do {
            let response = try await execute(request, endpoint: endpoint, environment: environment, context: context)
            let value = try decoder.decode(E.Response.self, from: response)
            if let cache, let cacheKey, let ttl = cachePolicy.storageTTL, Self.isStorable(response) {
                await cache.store(response, for: cacheKey, ttl: ttl)
            }
            return NetworkResponse(value: value, response: response, isFromCache: false)
        } catch {
            let networkError = NetworkError(error)
            // Offline fallback: any cached copy, even stale, beats an error screen.
            if case .networkFirst = cachePolicy, networkError.isConnectivityFailure,
               let cache, let cacheKey,
               let entry = await cache.cachedResponse(for: cacheKey),
               let value = try? decoder.decode(E.Response.self, from: entry.response) {
                log(.cacheHit(url: request.url, isExpired: entry.isExpired, context: context), environment)
                return NetworkResponse(value: value, response: entry.response, isFromCache: true)
            }
            throw networkError
        }
    }

    /// The retry loop.
    private func execute<E: Endpoint>(
        _ request: URLRequest,
        endpoint: E,
        environment: NetworkEnvironment,
        context: RequestContext
    ) async throws -> HTTPResponse {
        let retryPolicy = endpoint.retryPolicy ?? configuration.retryPolicy
        let clock = ContinuousClock()
        let start = clock.now
        var attempt = 1

        while true {
            let attemptContext = context.withAttempt(attempt)
            do {
                return try await sendAuthorized(request, endpoint: endpoint, environment: environment, context: attemptContext)
            } catch {
                let networkError = NetworkError(error)
                // Cancellation is never retried, whatever the policy says.
                if networkError == .cancelled || Task.isCancelled {
                    throw NetworkError.cancelled
                }
                let retryContext = RetryContext(
                    method: endpoint.method,
                    attempt: attempt,
                    error: networkError,
                    elapsed: (clock.now - start).timeInterval
                )
                guard let delay = retryPolicy.retryDelay(for: retryContext) else {
                    throw networkError
                }
                log(.retry(delay: delay, error: networkError, context: attemptContext), environment)
                try await sleep(delay)
                attempt += 1
            }
        }
    }

    /// One attempt, including the token refresh + single replay on `401`.
    private func sendAuthorized<E: Endpoint>(
        _ request: URLRequest,
        endpoint: E,
        environment: NetworkEnvironment,
        context: RequestContext
    ) async throws -> HTTPResponse {
        guard endpoint.auth == .bearer else {
            return try validate(await send(request, environment: environment, context: context))
        }
        guard let authManager = configuration.authManager else {
            throw NetworkError.missingCredentials
        }

        let token = try await authManager.validAccessToken()
        var response = try await send(Self.authorize(request, with: token), environment: environment, context: context)

        if response.statusCode == 401,
           let refreshedToken = try await authManager.accessTokenAfterUnauthorized(rejectedAccessToken: token) {
            response = try await send(Self.authorize(request, with: refreshedToken), environment: environment, context: context)
        }
        return try validate(response)
    }

    /// One round trip: interceptors, transport, logging.
    private func send(_ request: URLRequest, environment: NetworkEnvironment, context: RequestContext) async throws -> HTTPResponse {
        var request = request
        for interceptor in configuration.requestInterceptors {
            request = try await interceptor.intercept(request, context: context)
        }
        log(.request(request, context: context), environment)

        let clock = ContinuousClock()
        let start = clock.now
        do {
            var response = try await configuration.transport.send(request)
            for interceptor in configuration.responseInterceptors.reversed() {
                response = try await interceptor.intercept(response, for: request, context: context)
            }
            log(.response(response, request: request, duration: (clock.now - start).timeInterval, context: context), environment)
            return response
        } catch {
            log(.failure(NetworkError(error), request: request, duration: (clock.now - start).timeInterval, context: context), environment)
            throw error
        }
    }

    private func validate(_ response: HTTPResponse) throws -> HTTPResponse {
        guard configuration.acceptableStatusCodes.contains(response.statusCode) else {
            throw NetworkError.httpStatus(HTTPErrorResponse(response))
        }
        return response
    }

    private func log(_ event: NetworkLogEvent, _ environment: NetworkEnvironment) {
        guard environment.logLevel > .off, let logger = configuration.logger else { return }
        logger.log(event, level: environment.logLevel)
    }

    private static func authorize(_ request: URLRequest, with token: String) -> URLRequest {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: HTTPHeaderField.authorization)
        return request
    }

    /// Respects a server's `Cache-Control: no-store`.
    private static func isStorable(_ response: HTTPResponse) -> Bool {
        let cacheControl = response.headers[HTTPHeaderField.cacheControl]?.lowercased() ?? ""
        return !cacheControl.contains("no-store")
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
