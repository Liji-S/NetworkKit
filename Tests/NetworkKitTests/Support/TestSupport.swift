import Foundation
import os
import Testing
@testable import NetworkKit
import NetworkKitTesting

struct User: Codable, Sendable, Equatable {
    let id: Int
    let name: String
}

extension NetworkEnvironment {
    static let test = NetworkEnvironment(name: "test", baseURL: URL(string: "https://api.example.com/v1")!)
}

/// A controllable clock for TTL and expiry tests.
final class TestClock: Sendable {
    private let state: OSAllocatedUnfairLock<Date>

    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        state = OSAllocatedUnfairLock(initialState: start)
    }

    var now: Date { state.withLock { $0 } }

    func advance(by seconds: TimeInterval) {
        state.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

/// Records retry back-off delays instead of sleeping.
final class RecordingSleeper: Sendable {
    private let state = OSAllocatedUnfairLock<[TimeInterval]>(initialState: [])

    var delays: [TimeInterval] { state.withLock { $0 } }

    func sleep(_ seconds: TimeInterval) async throws {
        state.withLock { $0.append(seconds) }
        try Task.checkCancellation()
    }
}

actor Counter {
    private(set) var value = 0

    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }
}

actor Recorder {
    private(set) var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }
}

/// A refresher that counts calls, optionally waits, then returns or throws.
struct FakeRefresher: TokenRefresher {
    let counter: Counter
    var delay: TimeInterval = 0
    var result: @Sendable (_ call: Int) throws -> AuthTokens = { _ in
        AuthTokens(accessToken: "new", refreshToken: "refresh-2")
    }

    func refresh(using tokens: AuthTokens) async throws -> AuthTokens {
        let call = await counter.increment()
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        return try result(call)
    }
}

func makeClient(
    transport: MockHTTPTransport,
    authManager: AuthManager? = nil,
    retryPolicy: any RetryPolicy = NoRetryPolicy(),
    cache: (any ResponseCache)? = CacheManager(configuration: .memoryOnly),
    requestInterceptors: [any RequestInterceptor] = [],
    responseInterceptors: [any ResponseInterceptor] = [],
    sleeper: RecordingSleeper = RecordingSleeper()
) -> NetworkClient {
    let configuration = NetworkClientConfiguration(
        environment: .test,
        transport: transport,
        authManager: authManager,
        retryPolicy: retryPolicy,
        cache: cache,
        requestInterceptors: requestInterceptors,
        responseInterceptors: responseInterceptors,
        logger: nil
    )
    return NetworkClient(configuration: configuration) { try await sleeper.sleep($0) }
}

/// Runs `body` and returns the `NetworkError` it threw (or `nil` if it succeeded).
/// Any other error type is recorded as a test failure — NetworkKit must only ever surface `NetworkError`.
func captureNetworkError(_ body: () async throws -> Void) async -> NetworkError? {
    do {
        try await body()
        return nil
    } catch let error as NetworkError {
        return error
    } catch {
        Issue.record("Expected NetworkError, got \(type(of: error)): \(error)")
        return nil
    }
}
