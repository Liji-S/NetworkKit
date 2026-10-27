import Foundation

/// Builds a `multipart/form-data` body (RFC 7578) for file and image uploads.
///
/// ```swift
/// var form = MultipartFormData()
/// form.append("Lab report", name: "title")
/// form.append(pdfData, name: "file", fileName: "report.pdf", mimeType: "application/pdf")
/// ```
///
/// The whole body is built in memory, so it suits typical document and image uploads rather
/// than multi-hundred-megabyte files.
public struct MultipartFormData: Sendable, Equatable {
    public struct Part: Sendable, Equatable {
        public let name: String
        public let fileName: String?
        public let mimeType: String?
        public let data: Data
    }

    public let boundary: String
    public private(set) var parts: [Part] = []

    public init(boundary: String = "NetworkKit-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    /// Appends a text field.
    public mutating func append(_ value: String, name: String) {
        parts.append(Part(name: name, fileName: nil, mimeType: nil, data: Data(value.utf8)))
    }

    /// Appends binary data, typically a file. `mimeType` defaults to `application/octet-stream`
    /// when a `fileName` is given.
    public mutating func append(_ data: Data, name: String, fileName: String? = nil, mimeType: String? = nil) {
        let resolvedMimeType = mimeType ?? (fileName != nil ? "application/octet-stream" : nil)
        parts.append(Part(name: name, fileName: fileName, mimeType: resolvedMimeType, data: data))
    }

    /// The encoded body.
    public func encoded() -> Data {
        var body = Data()
        for part in parts {
            body.append("--\(boundary)\r\n")
            var disposition = "Content-Disposition: form-data; name=\"\(Self.escape(part.name))\""
            if let fileName = part.fileName {
                disposition += "; filename=\"\(Self.escape(fileName))\""
            }
            body.append(disposition + "\r\n")
            if let mimeType = part.mimeType {
                body.append("Content-Type: \(mimeType)\r\n")
            }
            body.append("\r\n")
            body.append(part.data)
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")
        return body
    }

    /// Escapes quotes and line breaks in names/filenames as the HTML form-submission algorithm does,
    /// so user-provided filenames can't break out of the header.
    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
