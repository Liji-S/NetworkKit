import Foundation
import Testing
@testable import NetworkKit

@Suite("NetworkError mapping")
struct NetworkErrorTests {
    @Test(arguments: [
        (URLError.Code.notConnectedToInternet, NetworkError.noConnection),
        (.dataNotAllowed, .noConnection),
        (.timedOut, .timedOut),
        (.cancelled, .cancelled),
        (.badServerResponse, .invalidResponse)
    ])
    func mapsURLErrors(code: URLError.Code, expected: NetworkError) {
        #expect(NetworkError(URLError(code)) == expected)
    }

    @Test func connectionLostIsTransientAndConnectivityFailure() {
        let error = NetworkError(URLError(.networkConnectionLost))
        #expect(error.isTransientTransportFailure)
        #expect(error.isConnectivityFailure)
    }

    @Test func mapsCancellationError() {
        #expect(NetworkError(CancellationError()) == .cancelled)
    }

    @Test func passesNetworkErrorThrough() {
        #expect(NetworkError(NetworkError.cacheMiss) == .cacheMiss)
    }

    @Test func describesDecodingFailuresWithKeyPath() throws {
        let decoder = ResponseDecoder()
        let response = HTTPResponse(statusCode: 200, data: Data(#"{"id": 1}"#.utf8))
        do {
            _ = try decoder.decode(User.self, from: response)
            Issue.record("Expected decoding to fail")
        } catch {
            guard case .decodingFailed(let message) = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
            #expect(message.contains("keyNotFound 'name'"))
        }
    }

    @Test func exposesErrorBodyForAppErrorPayloads() throws {
        struct APIError: Decodable { let code: String }
        let error = NetworkError.httpStatus(HTTPErrorResponse(statusCode: 422, data: Data(#"{"code":"invalid_email"}"#.utf8)))
        guard case .httpStatus(let response) = error else { return }
        #expect(try response.decodeBody(APIError.self).code == "invalid_email")
        #expect(error.statusCode == 422)
    }

    @Test func providesUserFacingDescriptions() {
        #expect(NetworkError.noConnection.localizedDescription.contains("offline"))
        #expect(NetworkError.httpStatus(HTTPErrorResponse(statusCode: 404)).localizedDescription.contains("could not be found"))
    }
}
