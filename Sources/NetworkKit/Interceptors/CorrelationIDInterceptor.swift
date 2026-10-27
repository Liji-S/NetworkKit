import Foundation

/// Tags each request with `RequestContext.requestID` so client logs can be matched to server logs.
/// The ID is the same across retries of one logical request.
public struct CorrelationIDInterceptor: RequestInterceptor {
    private let headerName: String

    public init(headerName: String = "X-Request-ID") {
        self.headerName = headerName
    }

    public func intercept(_ request: URLRequest, context: RequestContext) async throws -> URLRequest {
        var request = request
        request.setValue(context.requestID.uuidString, forHTTPHeaderField: headerName)
        return request
    }
}
