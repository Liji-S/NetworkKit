import Foundation

/// Masks secrets before anything is logged: sensitive headers, query parameters and JSON body keys.
/// All name comparisons are case-insensitive.
public struct LogRedactor: Sendable {
    public static let placeholder = "<redacted>"

    public var redactedHeaders: Set<String>
    public var redactedQueryParameters: Set<String>
    public var redactedBodyKeys: Set<String>
    /// Longer bodies are truncated in logs.
    public var maxBodyLength: Int

    public init(
        redactedHeaders: Set<String> = [
            "authorization", "proxy-authorization", "cookie", "set-cookie",
            "x-api-key", "x-goog-api-key", "api-key"
        ],
        redactedQueryParameters: Set<String> = [
            "key", "api_key", "apikey", "token", "access_token", "refresh_token",
            "client_secret", "signature", "sig", "password"
        ],
        redactedBodyKeys: Set<String> = [
            "password", "token", "access_token", "accesstoken", "refresh_token", "refreshtoken",
            "id_token", "idtoken", "client_secret", "secret"
        ],
        maxBodyLength: Int = 4096
    ) {
        self.redactedHeaders = Set(redactedHeaders.map { $0.lowercased() })
        self.redactedQueryParameters = Set(redactedQueryParameters.map { $0.lowercased() })
        self.redactedBodyKeys = Set(redactedBodyKeys.map { $0.lowercased() })
        self.maxBodyLength = maxBodyLength
    }

    public func headers(_ headers: HTTPHeaders) -> String {
        headers
            .map { field in
                let value = redactedHeaders.contains(field.name.lowercased()) ? Self.placeholder : field.value
                return "\(field.name): \(value)"
            }
            .joined(separator: "\n")
    }

    public func url(_ url: URL?) -> String {
        guard let url else { return "<no url>" }
        guard
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let items = components.queryItems, !items.isEmpty
        else { return url.absoluteString }
        components.queryItems = items.map { item in
            redactedQueryParameters.contains(item.name.lowercased())
                ? URLQueryItem(name: item.name, value: Self.placeholder)
                : item
        }
        return components.string ?? url.absoluteString
    }

    /// A printable, redacted, length-capped version of a body, or `nil` when it is empty.
    public func body(_ data: Data?, contentType: String?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        let type = contentType?.lowercased() ?? ""

        if type.contains("multipart/") {
            return "<multipart body, \(data.count) bytes>"
        }
        if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let redacted = try? JSONSerialization.data(
               withJSONObject: redactJSON(json),
               options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
           ),
           let text = String(data: redacted, encoding: .utf8) {
            return truncate(text)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return "<binary body, \(data.count) bytes>"
        }
        if type.contains("x-www-form-urlencoded") {
            return truncate(redactForm(text))
        }
        return truncate(text)
    }

    private func redactJSON(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, nested) in dictionary {
                result[key] = redactedBodyKeys.contains(key.lowercased()) ? Self.placeholder : redactJSON(nested)
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map(redactJSON)
        }
        return value
    }

    private func redactForm(_ text: String) -> String {
        text
            .split(separator: "&", omittingEmptySubsequences: false)
            .map { pair in
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let name = String(parts[0])
                let decodedName = name.removingPercentEncoding?.lowercased() ?? name.lowercased()
                return redactedBodyKeys.contains(decodedName) ? "\(name)=\(Self.placeholder)" : String(pair)
            }
            .joined(separator: "&")
    }

    private func truncate(_ text: String) -> String {
        guard text.count > maxBodyLength else { return text }
        return String(text.prefix(maxBodyLength)) + "… (\(text.count - maxBodyLength) more characters)"
    }
}
