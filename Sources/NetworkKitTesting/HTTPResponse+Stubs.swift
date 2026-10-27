import Foundation
import NetworkKit

extension HTTPResponse {
    /// A JSON response encoding `value`.
    public static func json<T: Encodable>(
        _ value: T,
        statusCode: Int = 200,
        headers: HTTPHeaders = [:],
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> HTTPResponse {
        HTTPResponse(
            statusCode: statusCode,
            headers: headers.merging([HTTPHeaderField.contentType: "application/json"]),
            data: try encoder.encode(value)
        )
    }

    /// A JSON response from a literal string, e.g. `.json(#"{"id": 1}"#)`.
    public static func json(_ string: String, statusCode: Int = 200, headers: HTTPHeaders = [:]) -> HTTPResponse {
        HTTPResponse(
            statusCode: statusCode,
            headers: headers.merging([HTTPHeaderField.contentType: "application/json"]),
            data: Data(string.utf8)
        )
    }

    /// A response with the given status and optional body, e.g. `.status(204)` or `.status(503, headers: ["Retry-After": "1"])`.
    public static func status(_ statusCode: Int, headers: HTTPHeaders = [:], body: Data = Data()) -> HTTPResponse {
        HTTPResponse(statusCode: statusCode, headers: headers, data: body)
    }
}
