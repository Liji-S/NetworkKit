import Foundation

/// Turns a `DecodingError` into a readable message that includes the failing key path,
/// e.g. `"keyNotFound 'email' at user.profile"` — far more useful in logs than the default description.
enum DecodingErrorDescriber {
    static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            "keyNotFound '\(key.stringValue)' at \(path(context))"
        case .typeMismatch(let type, let context):
            "typeMismatch \(type) at \(path(context)): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            "valueNotFound \(type) at \(path(context))"
        case .dataCorrupted(let context):
            "dataCorrupted at \(path(context)): \(context.debugDescription)"
        @unknown default:
            String(describing: error)
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        let components = context.codingPath.map { key in
            key.intValue.map { "[\($0)]" } ?? key.stringValue
        }
        return components.isEmpty ? "<root>" : components.joined(separator: ".")
    }
}
