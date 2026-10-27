import Foundation
import Testing
import NetworkKit
import NetworkKitTesting

@Suite("MockNetworkClient")
struct MockNetworkClientTests {
    private struct FetchUser: Endpoint {
        typealias Response = User
        let id: Int
        var path: String { "users/\(id)" }
    }

    @Test func returnsStubbedValuesAndRecordsEndpoints() async throws {
        let client = MockNetworkClient()
        await client.stub(FetchUser.self) { endpoint in User(id: endpoint.id, name: "User \(endpoint.id)") }

        let user = try await client.request(FetchUser(id: 7))
        #expect(user == User(id: 7, name: "User 7"))
        #expect(await client.endpoints(of: FetchUser.self).map(\.id) == [7])
    }

    @Test func throwsStubbedErrors() async {
        let client = MockNetworkClient()
        await client.stub(FetchUser.self, error: .noConnection)
        let error = await captureNetworkError { _ = try await client.request(FetchUser(id: 1)) }
        #expect(error == .noConnection)
    }

    @Test func failsLoudlyForUnstubbedEndpoints() async {
        let client = MockNetworkClient()
        let error = await captureNetworkError { _ = try await client.request(FetchUser(id: 1)) }
        guard case .underlying(let message) = error else {
            Issue.record("Unexpected error \(String(describing: error))")
            return
        }
        #expect(message.contains("no stub"))
    }
}
