import Foundation
import Testing
@testable import EclipsePlexClient

@Suite(.serialized)
struct AppLogRedactionTests {
    @Test func redactsPlexTokenInURL() {
        let url = URL(string: "https://plex.local:32400/video?X-Plex-Token=abc123")!
        let redacted = AppLog.redactURL(url)!
        #expect(redacted.contains("***"))
        #expect(!redacted.contains("abc123"))
    }

    @Test func redactsTokenInPlainText() {
        let text = "Failed X-Plex-Token=supersecret"
        let redacted = AppLog.redact(text)
        #expect(!redacted.contains("supersecret"))
    }
}
