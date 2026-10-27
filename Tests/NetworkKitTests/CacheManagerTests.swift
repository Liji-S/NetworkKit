import Foundation
import Testing
import NetworkKit

@Suite("CacheManager")
struct CacheManagerTests {
    private let response = HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], data: Data("{}".utf8))

    @Test func returnsFreshEntryThenMarksItExpiredAfterTTL() async {
        let clock = TestClock()
        let cache = CacheManager(configuration: .memoryOnly, now: { clock.now })
        await cache.store(response, for: "https://a.com/x", ttl: 60)

        let fresh = await cache.cachedResponse(for: "https://a.com/x")
        #expect(fresh?.isExpired == false)
        #expect(fresh?.response == response)

        clock.advance(by: 61)
        let stale = await cache.cachedResponse(for: "https://a.com/x")
        #expect(stale?.isExpired == true)
    }

    @Test func evictsLeastRecentlyUsedEntries() async {
        let cache = CacheManager(configuration: .init(maxMemoryEntries: 2, diskCapacity: 0))
        await cache.store(response, for: "https://a.com/1", ttl: 60)
        await cache.store(response, for: "https://a.com/2", ttl: 60)
        _ = await cache.cachedResponse(for: "https://a.com/1") // 1 is now most recently used
        await cache.store(response, for: "https://a.com/3", ttl: 60)

        #expect(await cache.cachedResponse(for: "https://a.com/1") != nil)
        #expect(await cache.cachedResponse(for: "https://a.com/2") == nil)
        #expect(await cache.cachedResponse(for: "https://a.com/3") != nil)
    }

    @Test func removesEntries() async {
        let cache = CacheManager(configuration: .memoryOnly)
        await cache.store(response, for: "https://a.com/1", ttl: 60)
        await cache.store(response, for: "https://a.com/2", ttl: 60)

        await cache.removeResponse(for: "https://a.com/1")
        #expect(await cache.cachedResponse(for: "https://a.com/1") == nil)
        #expect(await cache.cachedResponse(for: "https://a.com/2") != nil)

        await cache.removeAll()
        #expect(await cache.cachedResponse(for: "https://a.com/2") == nil)
    }

    @Test func persistsToDiskWithExpiry() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkKitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestClock()
        // One memory slot: storing a second entry evicts the first, so reading the first back
        // must come from the disk tier. (A second CacheManager instance isn't used because
        // URLCache flushes to disk asynchronously; the writing instance sees its writes at once.)
        let configuration = CacheManager.Configuration(maxMemoryEntries: 1, diskCapacity: 10 * 1024 * 1024, diskDirectory: directory)
        let cache = CacheManager(configuration: configuration, now: { clock.now })

        await cache.store(response, for: "https://a.com/persisted", ttl: 60)
        await cache.store(response, for: "https://a.com/evictor", ttl: 60)

        let entry = try #require(await cache.cachedResponse(for: "https://a.com/persisted"))
        #expect(entry.response.data == response.data)
        #expect(entry.response.statusCode == 200)
        #expect(entry.response.headers["Content-Type"] == "application/json")
        #expect(entry.response.headers["X-NetworkKit-Expires-At"] == nil)
        #expect(entry.isExpired == false)
        #expect(abs(entry.expiresAt.timeIntervalSince(clock.now.addingTimeInterval(60))) < 0.001)

        clock.advance(by: 61)
        await cache.store(response, for: "https://a.com/evictor-2", ttl: 60)
        #expect(await cache.cachedResponse(for: "https://a.com/persisted")?.isExpired == true)
    }
}
