import Foundation

/// What a `RetryPolicy` knows about a failed attempt.
public struct RetryContext: Sendable {
    public let method: HTTPMethod
    /// Number of attempts made so far, so `1` after the first failure.
    public let attempt: Int
    public let error: NetworkError
    /// Time since the first attempt started.
    public let elapsed: TimeInterval

    public init(method: HTTPMethod, attempt: Int, error: NetworkError, elapsed: TimeInterval) {
        self.method = method
        self.attempt = attempt
        self.error = error
        self.elapsed = elapsed
    }
}
