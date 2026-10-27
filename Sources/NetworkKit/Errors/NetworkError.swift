import Foundation

/// Every failure surfaced by NetworkKit.
///
/// `NetworkClient` never throws raw `URLError`, `DecodingError` or `EncodingError` values —
/// they are mapped into one of these cases so callers handle a single, predictable error type.
public enum NetworkError: Error, Sendable, Equatable {
    /// The base URL and endpoint path could not form a valid URL.
    case invalidURL(String)
    /// The request body could not be encoded.
    case encodingFailed(String)
    /// The response body could not be decoded into the endpoint's `Response` type.
    case decodingFailed(String)
    /// The server answered with a status code outside the accepted range.
    case httpStatus(HTTPErrorResponse)
    /// The request exceeded its timeout.
    case timedOut
    /// The request was cancelled, usually because its `Task` was cancelled.
    case cancelled
    /// The device is offline or the connection dropped.
    case noConnection
    /// `CachePolicy.cacheOnly` was used and nothing was cached for the request.
    case cacheMiss
    /// The endpoint requires authentication but no tokens are stored or no `AuthManager` is configured.
    case missingCredentials
    /// Refreshing the access token failed. `sessionInvalidated` is `true` when the server rejected
    /// the refresh token itself and the stored tokens were cleared (the user must sign in again).
    case tokenRefreshFailed(reason: String, sessionInvalidated: Bool)
    /// The response was not an HTTP response.
    case invalidResponse
    /// Any other URL loading failure (TLS, DNS, host unreachable, …).
    case transport(code: Int, description: String)
    /// A failure NetworkKit does not recognise, e.g. thrown by a custom interceptor.
    case underlying(String)

    /// The HTTP status code, when the error came from a rejected response.
    public var statusCode: Int? {
        if case .httpStatus(let response) = self { response.statusCode } else { nil }
    }

    /// Whether the failure is a connectivity problem rather than a server or client error.
    /// `CachePolicy.networkFirst` falls back to stale cache on these.
    public var isConnectivityFailure: Bool {
        switch self {
        case .noConnection, .timedOut: true
        default: isTransientTransportFailure
        }
    }

    /// Transport failures that are usually temporary. `networkConnectionLost` is the classic
    /// "stale keep-alive / HTTP/2 connection" error and is almost always fixed by a retry.
    static let transientTransportCodes: Set<URLError.Code> = [
        .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost, .secureConnectionFailed
    ]

    /// Whether the failure is a transient transport problem worth retrying.
    public var isTransientTransportFailure: Bool {
        if case .transport(let code, _) = self {
            Self.transientTransportCodes.contains(URLError.Code(rawValue: code))
        } else {
            false
        }
    }
}

extension NetworkError {
    /// Maps any error into a `NetworkError`.
    public init(_ error: any Error) {
        switch error {
        case let error as NetworkError:
            self = error
        case is CancellationError:
            self = .cancelled
        case let error as URLError:
            self = Self.map(error)
        case let error as DecodingError:
            self = .decodingFailed(DecodingErrorDescriber.describe(error))
        case let error as EncodingError:
            self = .encodingFailed(String(describing: error))
        default:
            self = .underlying(String(describing: error))
        }
    }

    private static func map(_ error: URLError) -> NetworkError {
        switch error.code {
        case .cancelled:
            .cancelled
        case .timedOut:
            .timedOut
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            .noConnection
        case .badURL, .unsupportedURL:
            .invalidURL(error.failingURL?.absoluteString ?? error.localizedDescription)
        case .badServerResponse:
            .invalidResponse
        default:
            .transport(code: error.code.rawValue, description: error.localizedDescription)
        }
    }
}

extension NetworkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The request address is invalid."
        case .encodingFailed:
            "The request could not be prepared."
        case .decodingFailed:
            "The server response could not be read."
        case .httpStatus(let response):
            switch response.statusCode {
            case 401: "Your session has expired. Please sign in again."
            case 403: "You don't have permission to do that."
            case 404: "The requested item could not be found."
            case 429: "Too many requests. Please try again shortly."
            case 500...599: "The server is having trouble. Please try again later."
            default: "The request failed (status \(response.statusCode))."
            }
        case .timedOut:
            "The request timed out. Please try again."
        case .cancelled:
            "The request was cancelled."
        case .noConnection:
            "You appear to be offline. Check your connection and try again."
        case .cacheMiss:
            "No saved data is available."
        case .missingCredentials:
            "You need to sign in to continue."
        case .tokenRefreshFailed(_, let sessionInvalidated):
            sessionInvalidated
                ? "Your session has expired. Please sign in again."
                : "We couldn't refresh your session. Please try again."
        case .invalidResponse:
            "The server returned an unexpected response."
        case .transport:
            "A network error occurred. Please try again."
        case .underlying:
            "Something went wrong. Please try again."
        }
    }
}
