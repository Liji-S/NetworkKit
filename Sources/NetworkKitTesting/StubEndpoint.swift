import Foundation
import NetworkKit

/// A fully configurable endpoint for tests, so each test case doesn't need its own type.
public struct StubEndpoint<Response: Decodable & Sendable>: Endpoint {
    public var path: String
    public var baseURL: URL?
    public var method: HTTPMethod
    public var queryItems: [URLQueryItem]
    public var headers: HTTPHeaders
    public var body: RequestBody?
    public var auth: AuthRequirement
    public var cachePolicy: CachePolicy
    public var timeout: TimeInterval?
    public var retryPolicy: (any RetryPolicy)?
    public var name: String

    public init(
        path: String = "stub",
        baseURL: URL? = nil,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = [],
        headers: HTTPHeaders = [:],
        body: RequestBody? = nil,
        auth: AuthRequirement = .none,
        cachePolicy: CachePolicy = .networkOnly,
        timeout: TimeInterval? = nil,
        retryPolicy: (any RetryPolicy)? = nil,
        name: String = "StubEndpoint"
    ) {
        self.path = path
        self.baseURL = baseURL
        self.method = method
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.auth = auth
        self.cachePolicy = cachePolicy
        self.timeout = timeout
        self.retryPolicy = retryPolicy
        self.name = name
    }
}
