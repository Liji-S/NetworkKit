import Foundation
import Testing
import NetworkKit

// macOS only: on the iOS Simulator an SPM test bundle has no host app and therefore no
// keychain-access-groups entitlement, so every Keychain call fails with -34018
// (errSecMissingEntitlement). Apps always have that entitlement, so the store works there.
#if os(macOS)
@Suite("KeychainTokenStore", .serialized)
struct KeychainTokenStoreTests {
    /// A unique service per run so tests never touch real app items or each other.
    private let store = KeychainTokenStore(service: "NetworkKitTests.\(UUID().uuidString)")

    @Test func savesLoadsOverwritesAndClears() async throws {
        defer { Task { [store] in try? await store.clear() } }

        #expect(try await store.load() == nil)

        let first = AuthTokens(accessToken: "a1", refreshToken: "r1", expiresAt: Date(timeIntervalSince1970: 1_700_000_000))
        try await store.save(first)
        #expect(try await store.load() == first)

        let second = AuthTokens(accessToken: "a2", refreshToken: "r2")
        try await store.save(second)
        #expect(try await store.load() == second)

        try await store.clear()
        #expect(try await store.load() == nil)
    }

    @Test func clearingAnEmptyStoreSucceeds() async throws {
        try await store.clear()
    }
}
#endif
