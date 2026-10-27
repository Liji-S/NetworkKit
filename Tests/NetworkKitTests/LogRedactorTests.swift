import Foundation
import Testing
import NetworkKit

@Suite("LogRedactor")
struct LogRedactorTests {
    private let redactor = LogRedactor()

    @Test func redactsSensitiveHeaders() {
        let output = redactor.headers(["Authorization": "Bearer secret", "X-Goog-Api-Key": "k", "Accept": "application/json"])
        #expect(!output.contains("secret"))
        #expect(output.contains("Authorization: <redacted>"))
        #expect(output.contains("X-Goog-Api-Key: <redacted>"))
        #expect(output.contains("Accept: application/json"))
    }

    @Test func redactsSensitiveQueryParameters() {
        let url = URL(string: "https://places.googleapis.com/v1/photo/media?maxWidthPx=400&key=SECRET")!
        let output = redactor.url(url)
        #expect(!output.contains("SECRET"))
        #expect(output.contains("maxWidthPx=400"))
    }

    @Test func redactsNestedJSONBodyKeys() {
        let body = Data(#"{"user": {"email": "a@b.c", "password": "hunter2"}, "tokens": [{"refresh_token": "r"}]}"#.utf8)
        let output = redactor.body(body, contentType: "application/json") ?? ""
        #expect(!output.contains("hunter2"))
        #expect(!output.contains("\"r\""))
        #expect(output.contains("a@b.c"))
    }

    @Test func redactsFormFields() {
        let output = redactor.body(Data("username=ada&password=hunter2".utf8), contentType: "application/x-www-form-urlencoded")
        #expect(output == "username=ada&password=<redacted>")
    }

    @Test func summarisesMultipartAndBinaryBodies() {
        #expect(redactor.body(Data(count: 10), contentType: "multipart/form-data; boundary=x") == "<multipart body, 10 bytes>")
        #expect(redactor.body(Data([0xFF, 0xFE, 0xFD]), contentType: "image/jpeg") == "<binary body, 3 bytes>")
    }

    @Test func truncatesLongBodies() {
        let redactor = LogRedactor(maxBodyLength: 5)
        let output = redactor.body(Data("abcdefghij".utf8), contentType: "text/plain")
        #expect(output?.hasPrefix("abcde…") == true)
    }
}
