import Foundation

/// The body of a request and how to encode it.
public enum RequestBody: Sendable {
    /// Encoded with the client's `JSONEncoder`; sent as `application/json`.
    case json(any Encodable & Sendable)
    /// Sent as-is with the given content type (e.g. `image/jpeg`, or JSON from a custom encoder).
    case data(Data, contentType: String)
    /// Sent as `application/x-www-form-urlencoded`.
    case formURLEncoded([URLQueryItem])
    /// Sent as `multipart/form-data`, for file and image uploads.
    case multipart(MultipartFormData)

    /// Encodes the body, returning the bytes and the `Content-Type` to send them with.
    func encoded(using encoder: JSONEncoder) throws(NetworkError) -> (data: Data, contentType: String) {
        switch self {
        case .json(let value):
            do {
                return (try encoder.encode(value), "application/json")
            } catch {
                throw .encodingFailed(String(describing: error))
            }
        case .data(let data, let contentType):
            return (data, contentType)
        case .formURLEncoded(let items):
            return (Data(PercentEncoding.formEncoded(items).utf8), "application/x-www-form-urlencoded; charset=utf-8")
        case .multipart(let form):
            return (form.encoded(), form.contentType)
        }
    }
}
