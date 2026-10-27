import Foundation

/// Never retries.
public struct NoRetryPolicy: RetryPolicy {
    public init() {}

    public func retryDelay(for context: RetryContext) -> TimeInterval? {
        nil
    }
}
