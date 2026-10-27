import Foundation

/// Whether an endpoint needs the user's access token.
public enum AuthRequirement: Sendable, Equatable {
    /// Sent without credentials.
    case none
    /// Sent with `Authorization: Bearer <access token>` from the client's `AuthManager`.
    /// A `401` triggers one token refresh and one replay of the request.
    case bearer
}
