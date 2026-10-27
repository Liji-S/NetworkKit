import Foundation

/// Decides whether — and after how long — a failed request is attempted again.
///
/// Set a default on `NetworkClientConfiguration.retryPolicy` and override per endpoint via
/// `Endpoint.retryPolicy`. Cancellation is never retried, regardless of the policy.
public protocol RetryPolicy: Sendable {
    /// Returns the delay in seconds before the next attempt, or `nil` to stop and surface the error.
    func retryDelay(for context: RetryContext) -> TimeInterval?
}
