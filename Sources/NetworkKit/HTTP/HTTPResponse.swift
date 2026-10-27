import Foundation

/// A received HTTP response, as plain values.
///
/// Used throughout the pipeline (interceptors, cache, logging, mocks) instead of
/// `HTTPURLResponse` so it is trivially `Sendable`, `Equatable` and easy to construct in tests.
public struct HTTPResponse: Sendable, Equatable {
    public var statusCode: Int
    public var headers: HTTPHeaders
    public var url: URL?
    public var data: Data

    public init(statusCode: Int, headers: HTTPHeaders = [:], url: URL? = nil, data: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.url = url
        self.data = data
    }

    init(_ response: HTTPURLResponse, data: Data) {
        self.init(
            statusCode: response.statusCode,
            headers: HTTPHeaders(response),
            url: response.url,
            data: data
        )
    }
}
