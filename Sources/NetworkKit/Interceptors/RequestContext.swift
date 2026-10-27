import Foundation

/// Information about the logical request an interceptor or logger is handling.
public struct RequestContext: Sendable, Equatable {
    /// Stable across retries and the post-refresh replay — one ID per `client.request(_:)` call.
    public let requestID: UUID
    public let endpointName: String
    public let environmentName: String
    /// 1 for the first attempt, incremented for each retry.
    public let attempt: Int

    public init(requestID: UUID = UUID(), endpointName: String, environmentName: String, attempt: Int = 1) {
        self.requestID = requestID
        self.endpointName = endpointName
        self.environmentName = environmentName
        self.attempt = attempt
    }

    func withAttempt(_ attempt: Int) -> RequestContext {
        RequestContext(requestID: requestID, endpointName: endpointName, environmentName: environmentName, attempt: attempt)
    }
}
