import Foundation

/// Where and how requests are executed — kept separate from endpoint definitions so the same
/// endpoint runs unchanged against development, staging, production or a custom server.
///
/// ```swift
/// extension NetworkEnvironment {
///     static let production = NetworkEnvironment(
///         name: "production",
///         baseURL: URL(string: "https://api.example.com/v1")!,
///         defaultHeaders: ["X-Api-Key": AppConfig.apiKey]
///     )
/// }
/// ```
public struct NetworkEnvironment: Sendable, Equatable {
    public var name: String
    public var baseURL: URL
    /// Sent with every request; endpoint headers with the same name take precedence.
    public var defaultHeaders: HTTPHeaders
    /// Default per-request timeout in seconds; endpoints can override it.
    public var timeout: TimeInterval
    public var logLevel: NetworkLogLevel

    public init(
        name: String,
        baseURL: URL,
        defaultHeaders: HTTPHeaders = [:],
        timeout: TimeInterval = 30,
        logLevel: NetworkLogLevel = .off
    ) {
        self.name = name
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.timeout = timeout
        self.logLevel = logLevel
    }
}
