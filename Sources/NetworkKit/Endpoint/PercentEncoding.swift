import Foundation

/// Query and form encoding that is stricter than `URLComponents`.
///
/// `URLComponents.queryItems` leaves `+`, `&`-adjacent and other sub-delimiters unescaped; most
/// servers decode `+` as a space, so `"a+b"` would silently arrive as `"a b"`. These helpers
/// escape everything except RFC 3986 unreserved characters.
enum PercentEncoding {
    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// `name=value&name2=value2` for use as `URLComponents.percentEncodedQuery`.
    static func queryEncoded(_ items: [URLQueryItem]) -> String {
        items.map { item in
            let name = escape(item.name)
            guard let value = item.value else { return name }
            return "\(name)=\(escape(value))"
        }
        .joined(separator: "&")
    }

    /// `application/x-www-form-urlencoded` body: like a query, but spaces become `+`.
    static func formEncoded(_ items: [URLQueryItem]) -> String {
        items.map { item in
            "\(formEscape(item.name))=\(formEscape(item.value ?? ""))"
        }
        .joined(separator: "&")
    }

    private static func escape(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: unreserved) ?? string
    }

    private static func formEscape(_ string: String) -> String {
        string
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { escape(String($0)) }
            .joined(separator: "+")
    }
}
