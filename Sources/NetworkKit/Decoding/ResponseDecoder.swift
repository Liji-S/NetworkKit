import Foundation

/// Decodes a response body into an endpoint's `Response` type.
///
/// - `Data` receives the raw body unchanged.
/// - `EmptyResponse` succeeds regardless of the body.
/// - Anything else is decoded as JSON; failures become `.decodingFailed` with the failing key path.
public struct ResponseDecoder: Sendable {
    private let decoder: JSONDecoder

    public init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    public func decode<T: Decodable>(_ type: T.Type, from response: HTTPResponse) throws(NetworkError) -> T {
        if let data = response.data as? T {
            return data
        }
        if let empty = EmptyResponse() as? T {
            return empty
        }
        guard !response.data.isEmpty else {
            throw .decodingFailed("Empty response body for \(T.self); use EmptyResponse for endpoints without a body")
        }
        do {
            return try decoder.decode(T.self, from: response.data)
        } catch let error as DecodingError {
            throw .decodingFailed(DecodingErrorDescriber.describe(error))
        } catch {
            throw .decodingFailed(String(describing: error))
        }
    }
}
