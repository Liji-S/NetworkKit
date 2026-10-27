import Foundation
import os

/// Logs to the unified logging system (Xcode console, Console.app, `log stream`).
///
/// Method, status, timing and endpoint name are logged as public. URLs, headers and bodies are
/// redacted by `LogRedactor` *and* marked `.private`, so they are visible while debugging in
/// Xcode but hidden in logs collected from users' devices.
public struct OSLogNetworkLogger: NetworkLogger {
    private let logger: Logger
    private let redactor: LogRedactor

    public init(
        subsystem: String = Bundle.main.bundleIdentifier ?? "NetworkKit",
        category: String = "Network",
        redactor: LogRedactor = LogRedactor()
    ) {
        self.logger = Logger(subsystem: subsystem, category: category)
        self.redactor = redactor
    }

    public func log(_ event: NetworkLogEvent, level: NetworkLogLevel) {
        guard level > .off else { return }

        switch event {
        case .request(let request, let context):
            let summary = "→ \(tag(context)) \(request.httpMethod ?? "GET") \(context.endpointName)\(attemptSuffix(context))"
            let details = details(
                headers: HTTPHeaders(request.allHTTPHeaderFields ?? [:]),
                body: request.httpBody,
                contentType: request.value(forHTTPHeaderField: HTTPHeaderField.contentType),
                level: level
            )
            logger.info("\(summary, privacy: .public) \(redactor.url(request.url), privacy: .private)\(details, privacy: .private)")

        case .response(let response, let request, let duration, let context):
            let summary = "← \(tag(context)) \(response.statusCode) \(request.httpMethod ?? "GET") \(context.endpointName) (\(milliseconds(duration)))"
            let details = details(
                headers: response.headers,
                body: response.data,
                contentType: response.headers[HTTPHeaderField.contentType],
                level: level
            )
            let type: OSLogType = response.statusCode >= 400 ? .error : .info
            logger.log(level: type, "\(summary, privacy: .public) \(redactor.url(request.url), privacy: .private)\(details, privacy: .private)")

        case .failure(let error, let request, let duration, let context):
            let summary = "✕ \(tag(context)) \(request.httpMethod ?? "GET") \(context.endpointName) failed after \(milliseconds(duration)): \(Self.describe(error))"
            logger.error("\(summary, privacy: .public) \(redactor.url(request.url), privacy: .private)")

        case .retry(let delay, let error, let context):
            logger.notice("↻ \(tag(context), privacy: .public) \(context.endpointName, privacy: .public) retrying in \(milliseconds(delay), privacy: .public) after \(Self.describe(error), privacy: .public)")

        case .cacheHit(let url, let isExpired, let context):
            let freshness = isExpired ? "stale" : "fresh"
            logger.debug("◎ \(tag(context), privacy: .public) \(context.endpointName, privacy: .public) served \(freshness, privacy: .public) from cache \(redactor.url(url), privacy: .private)")
        }
    }

    private func details(headers: HTTPHeaders, body: Data?, contentType: String?, level: NetworkLogLevel) -> String {
        var lines: [String] = []
        if level >= .headers, !headers.isEmpty {
            lines.append(redactor.headers(headers))
        }
        if level >= .body, let body = redactor.body(body, contentType: contentType) {
            lines.append(body)
        }
        return lines.isEmpty ? "" : "\n" + lines.joined(separator: "\n")
    }

    /// Short request ID prefix so concurrent requests can be told apart in the console.
    private func tag(_ context: RequestContext) -> String {
        "[\(context.requestID.uuidString.prefix(8))]"
    }

    private func attemptSuffix(_ context: RequestContext) -> String {
        context.attempt > 1 ? " (attempt \(context.attempt))" : ""
    }

    private func milliseconds(_ interval: TimeInterval) -> String {
        "\(Int((interval * 1000).rounded())) ms"
    }

    /// Error summary that never includes response bodies (they may contain personal data).
    private static func describe(_ error: NetworkError) -> String {
        switch error {
        case .httpStatus(let response): "HTTP \(response.statusCode)"
        case .decodingFailed(let reason): "decoding failed: \(reason)"
        case .tokenRefreshFailed(_, let invalidated): "token refresh failed\(invalidated ? " (session invalidated)" : "")"
        case .transport(let code, _): "transport error \(code)"
        default: String(describing: error)
        }
    }
}
