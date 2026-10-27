import Foundation

/// Everything a `NetworkClient` needs, assembled once at the app's composition root.
public struct NetworkClientConfiguration: Sendable {
    public var environmentResolver: any EnvironmentResolver
    public var transport: any HTTPTransport
    /// Required for `.bearer` endpoints; they fail with `.missingCredentials` without it.
    public var authManager: AuthManager?
    /// Used when an endpoint doesn't specify its own.
    public var retryPolicy: any RetryPolicy
    /// `nil` disables caching entirely (cache policies then behave like `.networkOnly`,
    /// except `.cacheOnly`, which throws `.cacheMiss`).
    public var cache: (any ResponseCache)?
    /// Run in order before each send.
    public var requestInterceptors: [any RequestInterceptor]
    /// Run in reverse order on each response.
    public var responseInterceptors: [any ResponseInterceptor]
    /// Only called when the environment's `logLevel` is above `.off`.
    public var logger: (any NetworkLogger)?
    public var encoder: JSONEncoder
    public var decoder: JSONDecoder
    /// Statuses outside this range become `NetworkError.httpStatus`.
    public var acceptableStatusCodes: Range<Int>

    /// Creates a configuration that resolves its environment per request.
    ///
    /// `cache` defaults to a memory-only `CacheManager`. For persistence across launches pass
    /// `CacheManager()` (disk-backed) — give each client its own `diskDirectory`.
    public init(
        environmentResolver: any EnvironmentResolver,
        transport: any HTTPTransport = URLSessionTransport(),
        authManager: AuthManager? = nil,
        retryPolicy: any RetryPolicy = ExponentialBackoffRetryPolicy(),
        cache: (any ResponseCache)? = CacheManager(configuration: .memoryOnly),
        requestInterceptors: [any RequestInterceptor] = [],
        responseInterceptors: [any ResponseInterceptor] = [],
        logger: (any NetworkLogger)? = OSLogNetworkLogger(),
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        acceptableStatusCodes: Range<Int> = 200..<300
    ) {
        self.environmentResolver = environmentResolver
        self.transport = transport
        self.authManager = authManager
        self.retryPolicy = retryPolicy
        self.cache = cache
        self.requestInterceptors = requestInterceptors
        self.responseInterceptors = responseInterceptors
        self.logger = logger
        self.encoder = encoder
        self.decoder = decoder
        self.acceptableStatusCodes = acceptableStatusCodes
    }

    /// Convenience for a single, fixed environment.
    public init(
        environment: NetworkEnvironment,
        transport: any HTTPTransport = URLSessionTransport(),
        authManager: AuthManager? = nil,
        retryPolicy: any RetryPolicy = ExponentialBackoffRetryPolicy(),
        cache: (any ResponseCache)? = CacheManager(configuration: .memoryOnly),
        requestInterceptors: [any RequestInterceptor] = [],
        responseInterceptors: [any ResponseInterceptor] = [],
        logger: (any NetworkLogger)? = OSLogNetworkLogger(),
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        acceptableStatusCodes: Range<Int> = 200..<300
    ) {
        self.init(
            environmentResolver: StaticEnvironmentResolver(environment),
            transport: transport,
            authManager: authManager,
            retryPolicy: retryPolicy,
            cache: cache,
            requestInterceptors: requestInterceptors,
            responseInterceptors: responseInterceptors,
            logger: logger,
            encoder: encoder,
            decoder: decoder,
            acceptableStatusCodes: acceptableStatusCodes
        )
    }
}
