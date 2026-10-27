import Foundation

/// Retries transient failures with exponentially growing, jittered delays.
///
/// Delay for attempt *n* is `min(maxDelay, baseDelay × multiplierⁿ⁻¹)`, reduced by a random
/// fraction of up to `jitter` so many clients failing together don't retry in lockstep.
///
/// Defaults are conservative:
/// - Only idempotent methods are retried, so a `POST` is never silently sent twice.
///   Set `retriesNonIdempotentRequests` on endpoints that are safe to replay (e.g. with an idempotency key).
/// - Retried: timeouts, transient transport errors and statuses 408, 429, 500, 502, 503, 504.
/// - A server `Retry-After` header is honoured exactly; if it asks for longer than `maxDelay`, the
///   policy gives up instead of retrying early.
/// - `maxElapsed` caps the total time spent including the upcoming delay.
public struct ExponentialBackoffRetryPolicy: RetryPolicy {
    public var maxRetries: Int
    public var baseDelay: TimeInterval
    public var multiplier: Double
    public var maxDelay: TimeInterval
    /// Fraction (0...1) of each computed delay that may be randomly removed.
    public var jitter: Double
    public var maxElapsed: TimeInterval
    public var retryableStatusCodes: Set<Int>
    public var retriesNonIdempotentRequests: Bool
    public var respectsRetryAfter: Bool

    private let random: @Sendable () -> Double
    private let now: @Sendable () -> Date

    /// Creates a policy; see the type documentation for what each setting controls.
    ///
    /// `random` supplies values in `0..<1` for jitter and `now` resolves HTTP-date `Retry-After`
    /// values — inject fixed ones in tests.
    public init(
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 0.5,
        multiplier: Double = 2,
        maxDelay: TimeInterval = 30,
        jitter: Double = 0.5,
        maxElapsed: TimeInterval = 60,
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
        retriesNonIdempotentRequests: Bool = false,
        respectsRetryAfter: Bool = true,
        random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.multiplier = multiplier
        self.maxDelay = maxDelay
        self.jitter = min(max(jitter, 0), 1)
        self.maxElapsed = maxElapsed
        self.retryableStatusCodes = retryableStatusCodes
        self.retriesNonIdempotentRequests = retriesNonIdempotentRequests
        self.respectsRetryAfter = respectsRetryAfter
        self.random = random
        self.now = now
    }

    public func retryDelay(for context: RetryContext) -> TimeInterval? {
        guard context.attempt <= maxRetries else { return nil }
        guard context.method.isIdempotent || retriesNonIdempotentRequests else { return nil }
        guard isRetryable(context.error) else { return nil }

        let delay: TimeInterval
        if respectsRetryAfter, let serverDelay = retryAfterDelay(from: context.error) {
            guard serverDelay <= maxDelay else { return nil }
            delay = serverDelay
        } else {
            let exponential = baseDelay * pow(multiplier, Double(context.attempt - 1))
            delay = min(maxDelay, exponential) * (1 - jitter * random())
        }

        guard context.elapsed + delay <= maxElapsed else { return nil }
        return delay
    }

    private func isRetryable(_ error: NetworkError) -> Bool {
        switch error {
        case .timedOut:
            true
        case .httpStatus(let response):
            retryableStatusCodes.contains(response.statusCode)
        default:
            error.isTransientTransportFailure
        }
    }

    private func retryAfterDelay(from error: NetworkError) -> TimeInterval? {
        guard
            case .httpStatus(let response) = error,
            let value = response.headers[HTTPHeaderField.retryAfter]
        else { return nil }
        return RetryAfterParser.delay(from: value, now: now())
    }
}
