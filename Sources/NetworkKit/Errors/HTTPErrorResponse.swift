import Foundation

/// The details of a response whose status code was rejected by the client's validation.
public struct HTTPErrorResponse: Sendable, Equatable {
    public let statusCode: Int
    public let headers: HTTPHeaders
    public let url: URL?
    /// The raw body, so apps can decode their own API error payload.
    public let data: Data

    public init(statusCode: Int, headers: HTTPHeaders = [:], url: URL? = nil, data: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.url = url
        self.data = data
    }

    init(_ response: HTTPResponse) {
        self.init(statusCode: response.statusCode, headers: response.headers, url: response.url, data: response.data)
    }

    /// Decodes the error body into an app-defined error payload, e.g. `{"code": "...", "message": "..."}`.
    public func decodeBody<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder = JSONDecoder()) throws -> T {
        try decoder.decode(type, from: data)
    }
}
