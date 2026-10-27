import Foundation

/// How much request/response detail is logged. Each level includes the previous ones.
public enum NetworkLogLevel: Int, Sendable, Comparable {
    /// Nothing is logged.
    case off
    /// Method, URL, status code, duration, retries and failures.
    case basic
    /// Adds request and response headers (sensitive values redacted).
    case headers
    /// Adds request and response bodies (sensitive JSON keys redacted, size capped).
    case body

    public static func < (lhs: NetworkLogLevel, rhs: NetworkLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
