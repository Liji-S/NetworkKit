import Foundation

/// The default two-level `ResponseCache`: an in-memory LRU in front of a `URLCache` on disk.
///
/// Memory hits are instant; disk entries survive app relaunches and are promoted back into
/// memory when read. Each entry's expiry is stored alongside it, so TTLs hold across launches.
public actor CacheManager: ResponseCache {
    public struct Configuration: Sendable {
        /// Maximum number of responses kept in memory; least recently used are evicted first.
        public var maxMemoryEntries: Int
        /// Disk tier size in bytes; `0` disables the disk tier.
        public var diskCapacity: Int
        /// Where the disk tier lives. Defaults to `Caches/NetworkKit.ResponseCache`.
        public var diskDirectory: URL?

        public init(maxMemoryEntries: Int = 100, diskCapacity: Int = 50 * 1024 * 1024, diskDirectory: URL? = nil) {
            self.maxMemoryEntries = maxMemoryEntries
            self.diskCapacity = diskCapacity
            self.diskDirectory = diskDirectory
        }

        /// Memory only — nothing is written to disk.
        public static let memoryOnly = Configuration(diskCapacity: 0)
    }

    private struct Entry {
        let response: HTTPResponse
        let expiresAt: Date
    }

    /// Private header used to persist the expiry date with the disk entry.
    private static let expiresHeader = "X-NetworkKit-Expires-At"

    private let maxMemoryEntries: Int
    private let disk: URLCache?
    private let now: @Sendable () -> Date
    private var memory: [String: Entry] = [:]
    /// Keys from least to most recently used.
    private var recency: [String] = []

    /// Creates a cache with the given tiers. `now` is the clock used for TTL checks —
    /// inject a controllable one in tests.
    public init(configuration: Configuration = Configuration(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.maxMemoryEntries = max(1, configuration.maxMemoryEntries)
        self.now = now
        if configuration.diskCapacity > 0 {
            let directory = configuration.diskDirectory ?? FileManager.default
                .urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("NetworkKit.ResponseCache", isDirectory: true)
            disk = URLCache(memoryCapacity: 0, diskCapacity: configuration.diskCapacity, directory: directory)
        } else {
            disk = nil
        }
    }

    public func cachedResponse(for key: String) async -> CachedResponse? {
        let entry: Entry
        if let memoryEntry = memory[key] {
            entry = memoryEntry
            touch(key)
        } else if let diskEntry = readFromDisk(key) {
            entry = diskEntry
            insertInMemory(diskEntry, for: key)
        } else {
            return nil
        }
        return CachedResponse(response: entry.response, expiresAt: entry.expiresAt, isExpired: entry.expiresAt <= now())
    }

    public func store(_ response: HTTPResponse, for key: String, ttl: TimeInterval) async {
        let entry = Entry(response: response, expiresAt: now().addingTimeInterval(ttl))
        insertInMemory(entry, for: key)
        writeToDisk(entry, for: key)
    }

    public func removeResponse(for key: String) async {
        memory.removeValue(forKey: key)
        recency.removeAll { $0 == key }
        if let url = URL(string: key) {
            disk?.removeCachedResponse(for: URLRequest(url: url))
        }
    }

    public func removeAll() async {
        memory.removeAll()
        recency.removeAll()
        disk?.removeAllCachedResponses()
    }

    // MARK: - Memory tier

    private func insertInMemory(_ entry: Entry, for key: String) {
        memory[key] = entry
        touch(key)
        while recency.count > maxMemoryEntries {
            let evicted = recency.removeFirst()
            memory.removeValue(forKey: evicted)
        }
    }

    private func touch(_ key: String) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    // MARK: - Disk tier

    private func readFromDisk(_ key: String) -> Entry? {
        guard
            let disk, let url = URL(string: key),
            let cached = disk.cachedResponse(for: URLRequest(url: url)),
            let httpResponse = cached.response as? HTTPURLResponse
        else { return nil }

        var response = HTTPResponse(httpResponse, data: cached.data)
        guard
            let expiresValue = response.headers[Self.expiresHeader],
            let expiresInterval = TimeInterval(expiresValue)
        else { return nil }
        response.headers[Self.expiresHeader] = nil
        return Entry(response: response, expiresAt: Date(timeIntervalSince1970: expiresInterval))
    }

    private func writeToDisk(_ entry: Entry, for key: String) {
        guard let disk, let url = URL(string: key) else { return }
        var headers = entry.response.headers
        headers[Self.expiresHeader] = String(entry.expiresAt.timeIntervalSince1970)
        guard let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: entry.response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers.dictionary
        ) else { return }
        let cached = CachedURLResponse(response: httpResponse, data: entry.response.data, userInfo: nil, storagePolicy: .allowed)
        disk.storeCachedResponse(cached, for: URLRequest(url: url))
    }
}
