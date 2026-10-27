import Foundation

/// Observes or transforms incoming responses — metrics, analytics, validation, security checks.
///
/// Interceptors run in **reverse** configuration order, so the first interceptor wraps the whole
/// stack (it sees the request first and the response last). They run on every response, before
/// status validation, including error statuses. Throwing turns the response into a failure.
public protocol ResponseInterceptor: Sendable {
    func intercept(_ response: HTTPResponse, for request: URLRequest, context: RequestContext) async throws -> HTTPResponse
}
