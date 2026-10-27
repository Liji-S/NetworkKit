import Foundation

/// How an endpoint uses the response cache. Only `GET` requests are ever cached.
public enum CachePolicy: Sendable, Equatable {
    /// Always fetch from the network; never read or write the cache.
    case networkOnly
    /// Return a cached response younger than its TTL without touching the network; otherwise
    /// fetch, and cache the result for `ttl` seconds.
    case cacheFirst(ttl: TimeInterval)
    /// Never touch the network: return any cached response (even an expired one) or throw `.cacheMiss`.
    case cacheOnly
    /// Always fetch and cache the result for `ttl` seconds. If the fetch fails for connectivity
    /// reasons, fall back to any cached response, even an expired one (offline mode).
    case networkFirst(ttl: TimeInterval)

    /// How long a fetched response is kept, or `nil` when this policy never writes.
    var storageTTL: TimeInterval? {
        switch self {
        case .cacheFirst(let ttl), .networkFirst(let ttl): ttl
        case .networkOnly, .cacheOnly: nil
        }
    }
}
