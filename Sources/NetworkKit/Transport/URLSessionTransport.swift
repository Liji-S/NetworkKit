import Foundation

/// The production `HTTPTransport`, backed by `URLSession`.
///
/// Cancelling the calling `Task` cancels the underlying `URLSessionTask`.
public final class URLSessionTransport: HTTPTransport {
    private let session: URLSession
    private let metricsHandler: (@Sendable (NetworkMetrics) -> Void)?

    /// - Parameters:
    ///   - configuration: Defaults to `URLSessionTransport.defaultConfiguration()`.
    ///   - metricsHandler: Called once per completed task with DNS/TLS/transfer timings.
    ///     Called on a URLSession delegate queue — hop to the main actor yourself if needed.
    public convenience init(
        configuration: URLSessionConfiguration = URLSessionTransport.defaultConfiguration(),
        metricsHandler: (@Sendable (NetworkMetrics) -> Void)? = nil
    ) {
        self.init(session: URLSession(configuration: configuration), metricsHandler: metricsHandler)
    }

    public init(session: URLSession, metricsHandler: (@Sendable (NetworkMetrics) -> Void)? = nil) {
        self.session = session
        self.metricsHandler = metricsHandler
    }

    /// A configuration suited to NetworkKit:
    /// - `URLSession`'s own HTTP cache is disabled — caching is controlled per endpoint by
    ///   `CachePolicy`, so `.networkOnly` really means "fresh from the server".
    /// - `waitsForConnectivity` is off so offline requests fail fast with `.noConnection`
    ///   (letting `.networkFirst` fall back to cache) instead of hanging.
    public static func defaultConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        return configuration
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let delegate = metricsHandler.map(NetworkTaskMetricsDelegate.init(handler:))
        let (data, response) = try await session.data(for: request, delegate: delegate)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        return HTTPResponse(httpResponse, data: data)
    }
}
