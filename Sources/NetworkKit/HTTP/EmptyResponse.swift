import Foundation

/// Response type for endpoints whose success response has no meaningful body (e.g. `204 No Content`).
///
/// Any body the server does send is ignored.
public struct EmptyResponse: Decodable, Sendable, Equatable {
    public init() {}
}
