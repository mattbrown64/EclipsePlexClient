import Foundation
import Testing
@testable import EclipsePlexClient

@MainActor
struct AppDiagnosticsTests {
    @Test func exportContainsNoRawTokens() {
        KeychainStore.resetAllForTesting()
        defer { KeychainStore.resetAllForTesting() }
        KeychainStore.savePlexAccountToken("secret-token-xyz")

        let registry = PlexServerRegistry()
        let downloads = OfflineDownloadManager()
        let text = AppDiagnostics.exportText(registry: registry, downloadManager: downloads)
        #expect(!text.contains("secret-token-xyz"))
        #expect(text.contains(AppVersion.marketingVersion))
    }
}
