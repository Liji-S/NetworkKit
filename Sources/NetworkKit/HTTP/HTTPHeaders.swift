import Foundation

/// A case-insensitive collection of HTTP header fields.
///
/// Header names are case-insensitive (RFC 9110 §5.1), so `"content-type"` and `"Content-Type"`
/// address the same field. The most recently set spelling of a name is preserved for output.
public struct HTTPHeaders: Sendable, Equatable, ExpressibleByDictionaryLiteral, Sequence {
    public struct Field: Sendable, Equatable {
        public let name: String
        public let value: String
    }

    /// Keyed by the lowercased header name.
    private var storage: [String: Field] = [:]

    public init() {}

    public init(_ dictionary: [String: String]) {
        for (name, value) in dictionary {
            self[name] = value
        }
    }

    public init(dictionaryLiteral elements: (String, String)...) {
        for (name, value) in elements {
            self[name] = value
        }
    }

    /// Reads or writes a header value. Assigning `nil` removes the header.
    public subscript(name: String) -> String? {
        get { storage[name.lowercased()]?.value }
        set {
            if let newValue {
                storage[name.lowercased()] = Field(name: name, value: newValue)
            } else {
                storage.removeValue(forKey: name.lowercased())
            }
        }
    }

    public func contains(_ name: String) -> Bool {
        storage[name.lowercased()] != nil
    }

    public var isEmpty: Bool { storage.isEmpty }

    public var count: Int { storage.count }

    /// Returns a copy with `other`'s fields added; fields in `other` win on conflict.
    public func merging(_ other: HTTPHeaders) -> HTTPHeaders {
        var result = self
        for field in other {
            result[field.name] = field.value
        }
        return result
    }

    /// The headers as a plain dictionary, using each field's preserved spelling.
    public var dictionary: [String: String] {
        Dictionary(uniqueKeysWithValues: storage.values.map { ($0.name, $0.value) })
    }

    /// Fields sorted by lowercased name so iteration order is deterministic (logs, tests).
    public func makeIterator() -> IndexingIterator<[Field]> {
        storage.sorted { $0.key < $1.key }.map(\.value).makeIterator()
    }
}

extension HTTPHeaders {
    /// Builds headers from `HTTPURLResponse.allHeaderFields`, which is typed `[AnyHashable: Any]`.
    init(_ response: HTTPURLResponse) {
        self.init()
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String else { continue }
            self[name] = String(describing: value)
        }
    }
}
