import Foundation
import Testing
@testable import EclipsePlexClient

@Suite(.serialized)
struct KeychainStoreTests {
    @Test func accountTokenRoundTrip() {
        KeychainStore.resetAllForTesting()
        defer { KeychainStore.resetAllForTesting() }
        KeychainStore.savePlexAccountToken("secret-account")
        #expect(KeychainStore.loadPlexAccountToken() == "secret-account")
        KeychainStore.savePlexAccountToken(nil)
        #expect(KeychainStore.loadPlexAccountToken() == nil)
    }

    @Test func serverTokenRoundTrip() {
        KeychainStore.resetAllForTesting()
        defer { KeychainStore.resetAllForTesting() }
        let id = UUID()
        KeychainStore.setToken("server-tok", forServerID: id)
        #expect(KeychainStore.token(forServerID: id) == "server-tok")
        KeychainStore.setToken(nil, forServerID: id)
        #expect(KeychainStore.token(forServerID: id) == nil)
    }

    @Test func migratesLegacyUserDefaultsAndClearsAccountKey() {
        KeychainStore.resetAllForTesting()
        defer { KeychainStore.resetAllForTesting() }

        let legacyKey = "plexAccountAuthToken.v1"
        UserDefaults.standard.set("legacy-token", forKey: legacyKey)
        KeychainStore.migrateFromUserDefaultsIfNeeded()

        #expect(KeychainStore.loadPlexAccountToken() == "legacy-token")
        #expect(UserDefaults.standard.string(forKey: legacyKey) == nil)
    }

    @Test func persistedServerStripsTokenFromJSON() {
        KeychainStore.resetAllForTesting()
        defer { KeychainStore.resetAllForTesting() }

        let server = PlexServer(name: "S", hostDescription: "http://127.0.0.1:32400", accessToken: "tok")
        let stripped = server.persistedWithoutToken
        #expect(stripped.accessToken == nil)
        let data = try! JSONEncoder().encode([stripped])
        let json = String(data: data, encoding: .utf8)!
        #expect(!json.contains("tok"))
    }
}
