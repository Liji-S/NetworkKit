import Foundation

/// A decoded value together with the response metadata it came from.
public struct NetworkResponse<Value: Sendable>: Sendable {
    public let value: Value
    public let statusCode: Int
    /// Useful for pagination (`Link`), rate limits, ETags and similar.
    public let headers: HTTPHeaders
    /// `true` when served from the response cache rather than the network.
    public let isFromCache: Bool

    public init(value: Value, statusCode: Int, headers: HTTPHeaders = [:], isFromCache: Bool = false) {
        self.value = value
        self.statusCode = statusCode
        self.headers = headers
        self.isFromCache = isFromCache
    }

    init(value: Value, response: HTTPResponse, isFromCache: Bool) {
        self.init(value: value, statusCode: response.statusCode, headers: response.headers, isFromCache: isFromCache)
    }
}

extension NetworkResponse: Equatable where Value: Equatable {}
