import Foundation

/// Adds fixed headers to every request.
///
/// By default it doesn't overwrite headers the request already has (so endpoint headers win);
/// pass `overwrite: true` to force the values.
public struct HeadersInterceptor: RequestInterceptor {
    private let headers: HTTPHeaders
    private let overwrite: Bool

    public init(_ headers: HTTPHeaders, overwrite: Bool = false) {
        self.headers = headers
        self.overwrite = overwrite
    }

    public func intercept(_ request: URLRequest, context: RequestContext) async throws -> URLRequest {
        var request = request
        for field in headers where overwrite || request.value(forHTTPHeaderField: field.name) == nil {
            request.setValue(field.value, forHTTPHeaderField: field.name)
        }
        return request
    }
}
