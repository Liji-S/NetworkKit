import Foundation
import Testing
@testable import NetworkKit

@Suite("ExponentialBackoffRetryPolicy")
struct RetryPolicyTests {
    private let serverError = NetworkError.httpStatus(HTTPErrorResponse(statusCode: 503))

    private func context(
        _ attempt: Int,
        method: HTTPMethod = .get,
        error: NetworkError? = nil,
        elapsed: TimeInterval = 0
    ) -> RetryContext {
        RetryContext(method: method, attempt: attempt, error: error ?? serverError, elapsed: elapsed)
    }

    @Test func growsExponentiallyAndStopsAfterMaxRetries() {
        let policy = ExponentialBackoffRetryPolicy(maxRetries: 3, baseDelay: 0.5, jitter: 0)
        #expect(policy.retryDelay(for: context(1)) == 0.5)
        #expect(policy.retryDelay(for: context(2)) == 1.0)
        #expect(policy.retryDelay(for: context(3)) == 2.0)
        #expect(policy.retryDelay(for: context(4)) == nil)
    }

    @Test func capsAtMaxDelay() {
        let policy = ExponentialBackoffRetryPolicy(maxRetries: 10, baseDelay: 1, maxDelay: 4, jitter: 0, maxElapsed: 1000)
        #expect(policy.retryDelay(for: context(6)) == 4)
    }

    @Test func appliesJitter() {
        let policy = ExponentialBackoffRetryPolicy(baseDelay: 1, jitter: 0.5, random: { 0.5 })
        #expect(policy.retryDelay(for: context(1)) == 0.75)
    }

    @Test func doesNotRetryNonIdempotentRequestsUnlessAllowed() {
        let strict = ExponentialBackoffRetryPolicy(jitter: 0)
        #expect(strict.retryDelay(for: context(1, method: .post)) == nil)
        #expect(strict.retryDelay(for: context(1, method: .patch)) == nil)

        let lenient = ExponentialBackoffRetryPolicy(jitter: 0, retriesNonIdempotentRequests: true)
        #expect(lenient.retryDelay(for: context(1, method: .post)) == 0.5)
    }

    @Test(arguments: [
        (NetworkError.httpStatus(HTTPErrorResponse(statusCode: 503)), true),
        (.httpStatus(HTTPErrorResponse(statusCode: 429)), true),
        (.timedOut, true),
        (NetworkError(URLError(.networkConnectionLost)), true),
        (.httpStatus(HTTPErrorResponse(statusCode: 400)), false),
        (.httpStatus(HTTPErrorResponse(statusCode: 401)), false),
        (.httpStatus(HTTPErrorResponse(statusCode: 404)), false),
        (.decodingFailed("x"), false),
        (.cancelled, false),
        (.noConnection, false)
    ])
    func retriesOnlyTransientFailures(error: NetworkError, shouldRetry: Bool) {
        let policy = ExponentialBackoffRetryPolicy(jitter: 0)
        #expect((policy.retryDelay(for: context(1, error: error)) != nil) == shouldRetry)
    }

    @Test func honoursRetryAfterSeconds() {
        let policy = ExponentialBackoffRetryPolicy(jitter: 0)
        let error = NetworkError.httpStatus(HTTPErrorResponse(statusCode: 429, headers: ["Retry-After": "7"]))
        #expect(policy.retryDelay(for: context(1, error: error)) == 7)
    }

    @Test func honoursRetryAfterHTTPDate() {
        let now = Date(timeIntervalSince1970: 1_445_412_475) // Wed, 21 Oct 2015 07:27:55 GMT
        let policy = ExponentialBackoffRetryPolicy(jitter: 0, now: { now })
        let error = NetworkError.httpStatus(HTTPErrorResponse(
            statusCode: 503,
            headers: ["Retry-After": "Wed, 21 Oct 2015 07:28:00 GMT"]
        ))
        #expect(policy.retryDelay(for: context(1, error: error)) == 5)
    }

    @Test func givesUpWhenRetryAfterExceedsMaxDelay() {
        let policy = ExponentialBackoffRetryPolicy(maxDelay: 30, jitter: 0)
        let error = NetworkError.httpStatus(HTTPErrorResponse(statusCode: 503, headers: ["Retry-After": "120"]))
        #expect(policy.retryDelay(for: context(1, error: error)) == nil)
    }

    @Test func respectsOverallTimeBudget() {
        let policy = ExponentialBackoffRetryPolicy(baseDelay: 2, jitter: 0, maxElapsed: 10)
        #expect(policy.retryDelay(for: context(1, elapsed: 7)) == 2)
        #expect(policy.retryDelay(for: context(1, elapsed: 9)) == nil)
    }

    @Test func noRetryPolicyNeverRetries() {
        #expect(NoRetryPolicy().retryDelay(for: context(1)) == nil)
    }
}
