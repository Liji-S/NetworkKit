import Foundation

/// A response read from a `ResponseCache`.
public struct CachedResponse: Sendable, Equatable {
    public let response: HTTPResponse
    public let expiresAt: Date
    /// Whether the entry's TTL had passed at the moment it was looked up.
    public let isExpired: Bool

    public init(response: HTTPResponse, expiresAt: Date, isExpired: Bool) {
        self.response = response
        self.expiresAt = expiresAt
        self.isExpired = isExpired
    }
}
