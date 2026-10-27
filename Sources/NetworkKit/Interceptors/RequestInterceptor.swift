import Foundation

/// Modifies outgoing requests — signing, correlation IDs, custom headers, metadata.
///
/// Interceptors run in the order they are configured, immediately before each send, so they also
/// run for retries and for the replay after a token refresh (keeping signatures/timestamps fresh).
/// The `Authorization` header is already set when they run. Throwing aborts the request.
public protocol RequestInterceptor: Sendable {
    func intercept(_ request: URLRequest, context: RequestContext) async throws -> URLRequest
}
