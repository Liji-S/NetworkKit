import Foundation

/// URL loading timings for one task, taken from its final transaction (after redirects).
/// Phases that did not happen — e.g. DNS/TLS on a reused connection — are `nil`.
public struct NetworkMetrics: Sendable, Equatable {
    public let url: URL?
    public let method: String?
    public let statusCode: Int?
    /// From task creation to completion, including redirects.
    public let totalDuration: TimeInterval
    public let dnsDuration: TimeInterval?
    /// TCP (or QUIC) connection establishment, including TLS.
    public let connectDuration: TimeInterval?
    public let tlsDuration: TimeInterval?
    /// Time spent sending the request.
    public let requestDuration: TimeInterval?
    /// From the request being sent to the first response byte — mostly server processing time.
    public let timeToFirstByte: TimeInterval?
    /// Time spent receiving the response.
    public let responseDuration: TimeInterval?
    public let isReusedConnection: Bool
    /// e.g. `"h2"`, `"h3"`, `"http/1.1"`.
    public let networkProtocol: String?
    public let requestBodyBytes: Int64
    public let responseBodyBytes: Int64
    public let redirectCount: Int

    public init(_ metrics: URLSessionTaskMetrics) {
        let transaction = metrics.transactionMetrics.last
        url = transaction?.request.url
        method = transaction?.request.httpMethod
        statusCode = (transaction?.response as? HTTPURLResponse)?.statusCode
        totalDuration = metrics.taskInterval.duration
        dnsDuration = Self.span(transaction?.domainLookupStartDate, transaction?.domainLookupEndDate)
        connectDuration = Self.span(transaction?.connectStartDate, transaction?.connectEndDate)
        tlsDuration = Self.span(transaction?.secureConnectionStartDate, transaction?.secureConnectionEndDate)
        requestDuration = Self.span(transaction?.requestStartDate, transaction?.requestEndDate)
        timeToFirstByte = Self.span(transaction?.requestEndDate, transaction?.responseStartDate)
        responseDuration = Self.span(transaction?.responseStartDate, transaction?.responseEndDate)
        isReusedConnection = transaction?.isReusedConnection ?? false
        networkProtocol = transaction?.networkProtocolName
        requestBodyBytes = transaction?.countOfRequestBodyBytesSent ?? 0
        responseBodyBytes = transaction?.countOfResponseBodyBytesReceived ?? 0
        redirectCount = metrics.redirectCount
    }

    private static func span(_ start: Date?, _ end: Date?) -> TimeInterval? {
        guard let start, let end else { return nil }
        return end.timeIntervalSince(start)
    }
}
