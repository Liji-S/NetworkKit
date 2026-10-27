import Foundation
import Testing
@testable import NetworkKit

@Suite("MultipartFormData")
struct MultipartFormDataTests {
    @Test func encodesExactRFC7578Layout() {
        var form = MultipartFormData(boundary: "B")
        form.append("Hello", name: "title")
        form.append(Data("abc".utf8), name: "file", fileName: "a.txt", mimeType: "text/plain")

        let expected = """
        --B\r
        Content-Disposition: form-data; name="title"\r
        \r
        Hello\r
        --B\r
        Content-Disposition: form-data; name="file"; filename="a.txt"\r
        Content-Type: text/plain\r
        \r
        abc\r
        --B--\r

        """
        #expect(String(data: form.encoded(), encoding: .utf8) == expected)
        #expect(form.contentType == "multipart/form-data; boundary=B")
    }

    @Test func escapesQuotesAndLineBreaksInNames() {
        var form = MultipartFormData(boundary: "B")
        form.append(Data(), name: "file", fileName: "my\"file\r\n.txt")
        let body = String(data: form.encoded(), encoding: .utf8) ?? ""
        #expect(body.contains(#"filename="my%22file%0D%0A.txt""#))
    }

    @Test func defaultsFileMimeTypeToOctetStream() {
        var form = MultipartFormData(boundary: "B")
        form.append(Data([0x01]), name: "blob", fileName: "blob.bin")
        #expect(form.parts.first?.mimeType == "application/octet-stream")
    }

    @Test func isUsableAsRequestBody() throws {
        var form = MultipartFormData(boundary: "B")
        form.append("1", name: "a")
        let encoded = try RequestBody.multipart(form).encoded(using: JSONEncoder())
        #expect(encoded.contentType == "multipart/form-data; boundary=B")
        #expect(encoded.data == form.encoded())
    }
}
