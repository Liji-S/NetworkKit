import Foundation

/// Storage for successful `GET` responses, keyed by absolute URL.
///
/// `CacheManager` is the default implementation; conform your own type to use different storage.
/// Responses for authenticated endpoints are cached too — call `NetworkClient.clearCache()` on
/// sign-out so one user's data is never served to the next.
public protocol ResponseCache: Sendable {
    /// Returns the entry for `key`, including expired ones (callers decide whether stale is acceptable).
    func cachedResponse(for key: String) async -> CachedResponse?
    func store(_ response: HTTPResponse, for key: String, ttl: TimeInterval) async
    func removeResponse(for key: String) async
    func removeAll() async
}
