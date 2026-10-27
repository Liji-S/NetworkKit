import Foundation

/// The credentials NetworkKit manages for `.bearer` endpoints.
public struct AuthTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    /// Without a refresh token, an expired/rejected access token can't be renewed.
    public var refreshToken: String?
    /// When the access token expires. `nil` means unknown — it is used until the server rejects it.
    public var expiresAt: Date?

    public init(accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Convenience for OAuth-style responses that return `expires_in` seconds.
    public init(accessToken: String, refreshToken: String? = nil, expiresIn: TimeInterval, now: Date = Date()) {
        self.init(accessToken: accessToken, refreshToken: refreshToken, expiresAt: now.addingTimeInterval(expiresIn))
    }

    /// Whether the access token is expired or will expire within `leeway` seconds.
    public func isExpired(leeway: TimeInterval = 0, now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.addingTimeInterval(-leeway) <= now
    }
}
