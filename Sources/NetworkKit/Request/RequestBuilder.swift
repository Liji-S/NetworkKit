import Foundation

/// Turns an `Endpoint` plus a `NetworkEnvironment` into a `URLRequest`.
///
/// Authentication is deliberately not handled here — the client injects the token later in
/// the pipeline so a refreshed token can be applied when a request is replayed.
public struct RequestBuilder: Sendable {
    private let encoder: JSONEncoder

    public init(encoder: JSONEncoder = JSONEncoder()) {
        self.encoder = encoder
    }

    public func makeRequest<E: Endpoint>(for endpoint: E, environment: NetworkEnvironment) throws(NetworkError) -> URLRequest {
        let url = try makeURL(for: endpoint, environment: environment)
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = endpoint.timeout ?? environment.timeout

        // Precedence, lowest to highest: environment defaults → body content type → endpoint headers.
        var headers = environment.defaultHeaders
        if let body = endpoint.body {
            let encoded = try body.encoded(using: encoder)
            request.httpBody = encoded.data
            headers[HTTPHeaderField.contentType] = encoded.contentType
        }
        headers = headers.merging(endpoint.headers)
        if !headers.contains(HTTPHeaderField.accept) {
            headers[HTTPHeaderField.accept] = "application/json"
        }
        for field in headers {
            request.setValue(field.value, forHTTPHeaderField: field.name)
        }
        return request
    }

    private func makeURL<E: Endpoint>(for endpoint: E, environment: NetworkEnvironment) throws(NetworkError) -> URL {
        let baseURL = endpoint.baseURL ?? environment.baseURL
        let path = endpoint.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let pathURL = path.isEmpty ? baseURL : baseURL.appendingPathComponent(path)

        guard var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false) else {
            throw .invalidURL(pathURL.absoluteString)
        }
        if !endpoint.queryItems.isEmpty {
            // Keep any query already present on the base URL, then append the endpoint's items.
            let existing = components.percentEncodedQuery.flatMap { $0.isEmpty ? nil : $0 }
            let added = PercentEncoding.queryEncoded(endpoint.queryItems)
            components.percentEncodedQuery = [existing, added].compactMap { $0 }.joined(separator: "&")
        }
        guard
            let url = components.url,
            let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
            url.host != nil
        else {
            throw .invalidURL(components.string ?? pathURL.absoluteString)
        }
        return url
    }
}
