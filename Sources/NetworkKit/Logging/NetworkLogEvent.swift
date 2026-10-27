import Foundation

/// Something worth logging that happened while executing a request.
public enum NetworkLogEvent: Sendable {
    /// About to send (after interceptors ran).
    case request(URLRequest, context: RequestContext)
    /// A response arrived, whatever its status.
    case response(HTTPResponse, request: URLRequest, duration: TimeInterval, context: RequestContext)
    /// The attempt failed before a response arrived, or the response was rejected.
    case failure(NetworkError, request: URLRequest, duration: TimeInterval, context: RequestContext)
    /// The attempt failed and will be retried after `delay` seconds.
    case retry(delay: TimeInterval, error: NetworkError, context: RequestContext)
    /// A response was served from the cache.
    case cacheHit(url: URL?, isExpired: Bool, context: RequestContext)
}
