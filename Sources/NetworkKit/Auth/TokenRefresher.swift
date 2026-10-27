import Foundation

/// Exchanges the current tokens for new ones.
///
/// `EndpointTokenRefresher` covers the common "POST the refresh token to an endpoint" flow;
/// conform your own type for anything else (e.g. an OAuth SDK).
public protocol TokenRefresher: Sendable {
    /// Throw `NetworkError.httpStatus` with 400/401/403 when the server rejects the refresh token —
    /// `AuthManager` treats those as "session over" and clears the stored tokens.
    func refresh(using tokens: AuthTokens) async throws -> AuthTokens
}
