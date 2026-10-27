import Foundation
import Testing
@testable import NetworkKit
import NetworkKitTesting

@Suite("RequestBuilder")
struct RequestBuilderTests {
    private let builder = RequestBuilder()

    @Test func joinsBaseURLAndPathRegardlessOfSlashes() throws {
        for path in ["users/42", "/users/42", "/users/42/"] {
            let request = try builder.makeRequest(for: StubEndpoint<User>(path: path), environment: .test)
            #expect(request.url?.absoluteString == "https://api.example.com/v1/users/42")
        }
    }

    @Test func endpointBaseURLOverridesEnvironment() throws {
        let endpoint = StubEndpoint<User>(path: "upload", baseURL: URL(string: "https://uploads.example.com")!)
        let request = try builder.makeRequest(for: endpoint, environment: .test)
        #expect(request.url?.absoluteString == "https://uploads.example.com/upload")
    }

    @Test func percentEncodesQueryStrictly() throws {
        let endpoint = StubEndpoint<User>(path: "search", queryItems: [
            URLQueryItem(name: "q", value: "a+b c"),
            URLQueryItem(name: "tag", value: "x&y=z"),
            URLQueryItem(name: "flag", value: nil)
        ])
        let request = try builder.makeRequest(for: endpoint, environment: .test)
        #expect(request.url?.query == "q=a%2Bb%20c&tag=x%26y%3Dz&flag")
    }

    @Test func keepsQueryAlreadyOnBaseURL() throws {
        var environment = NetworkEnvironment.test
        environment.baseURL = URL(string: "https://api.example.com/v1?version=2")!
        let endpoint = StubEndpoint<User>(path: "", queryItems: [URLQueryItem(name: "page", value: "3")])
        let request = try builder.makeRequest(for: endpoint, environment: environment)
        #expect(request.url?.query == "version=2&page=3")
    }

    @Test func endpointHeadersOverrideEnvironmentDefaults() throws {
        var environment = NetworkEnvironment.test
        environment.defaultHeaders = ["X-Client": "env", "X-Only-Env": "1"]
        let endpoint = StubEndpoint<User>(headers: ["x-client": "endpoint"])
        let request = try builder.makeRequest(for: endpoint, environment: environment)
        #expect(request.value(forHTTPHeaderField: "X-Client") == "endpoint")
        #expect(request.value(forHTTPHeaderField: "X-Only-Env") == "1")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func encodesJSONBody() throws {
        let endpoint = StubEndpoint<User>(method: .post, body: .json(User(id: 1, name: "Ada")))
        let request = try builder.makeRequest(for: endpoint, environment: .test)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let decoded = try JSONDecoder().decode(User.self, from: try #require(request.httpBody))
        #expect(decoded == User(id: 1, name: "Ada"))
    }

    @Test func endpointContentTypeOverridesBodyContentType() throws {
        let endpoint = StubEndpoint<User>(
            method: .post,
            headers: ["Content-Type": "application/vnd.api+json"],
            body: .json(User(id: 1, name: "Ada"))
        )
        let request = try builder.makeRequest(for: endpoint, environment: .test)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/vnd.api+json")
    }

    @Test func encodesFormBody() throws {
        let endpoint = StubEndpoint<User>(method: .post, body: .formURLEncoded([
            URLQueryItem(name: "name", value: "John Doe"),
            URLQueryItem(name: "city", value: "São Paulo&Co")
        ]))
        let request = try builder.makeRequest(for: endpoint, environment: .test)
        let body = String(data: try #require(request.httpBody), encoding: .utf8)
        #expect(body == "name=John+Doe&city=S%C3%A3o+Paulo%26Co")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/x-www-form-urlencoded") == true)
    }

    @Test func appliesTimeouts() throws {
        let defaultRequest = try builder.makeRequest(for: StubEndpoint<User>(), environment: .test)
        #expect(defaultRequest.timeoutInterval == 30)
        let custom = try builder.makeRequest(for: StubEndpoint<User>(timeout: 5), environment: .test)
        #expect(custom.timeoutInterval == 5)
    }

    @Test func rejectsNonHTTPURLs() {
        let endpoint = StubEndpoint<User>(path: "x", baseURL: URL(string: "file:///tmp")!)
        #expect(throws: NetworkError.self) {
            try builder.makeRequest(for: endpoint, environment: .test)
        }
    }
}
