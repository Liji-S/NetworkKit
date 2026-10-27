import Foundation

/// A typed description of one API call.
///
/// The associated `Response` type binds the request to what it returns, so
/// `client.request(FetchUserEndpoint(id: "42"))` is compiler-checked to produce a `UserDTO`.
///
/// ```swift
/// struct FetchUserEndpoint: Endpoint {
///     typealias Response = UserDTO
///     let id: String
///     var path: String { "users/\(id)" }
///     var auth: AuthRequirement { .bearer }
///     var cachePolicy: CachePolicy { .cacheFirst(ttl: 60) }
/// }
/// ```
///
/// Only `path` (and `Response`) are required; everything else has a sensible default.
/// Use `Data` as `Response` to receive the raw body, or `EmptyResponse` when there is none.
public protocol Endpoint: Sendable {
    associatedtype Response: Decodable & Sendable

    /// Path appended to the environment's base URL, e.g. `"users/42"`. Leading slashes are fine.
    var path: String { get }
    /// Overrides the environment's base URL for this endpoint (e.g. a separate upload host).
    var baseURL: URL? { get }
    var method: HTTPMethod { get }
    var queryItems: [URLQueryItem] { get }
    /// Endpoint headers override environment default headers with the same name.
    var headers: HTTPHeaders { get }
    var body: RequestBody? { get }
    var auth: AuthRequirement { get }
    /// Only honoured for `GET` requests; other methods always behave as `.networkOnly`.
    var cachePolicy: CachePolicy { get }
    /// Overrides the environment's default timeout.
    var timeout: TimeInterval? { get }
    /// Overrides the client's default retry policy.
    var retryPolicy: (any RetryPolicy)? { get }
    /// Name used in logs and passed to interceptors. Defaults to the type name.
    var name: String { get }
}

extension Endpoint {
    public var baseURL: URL? { nil }
    public var method: HTTPMethod { .get }
    public var queryItems: [URLQueryItem] { [] }
    public var headers: HTTPHeaders { [:] }
    public var body: RequestBody? { nil }
    public var auth: AuthRequirement { .none }
    public var cachePolicy: CachePolicy { .networkOnly }
    public var timeout: TimeInterval? { nil }
    public var retryPolicy: (any RetryPolicy)? { nil }
    public var name: String { String(describing: Self.self) }
}
