import Foundation
import Testing
@testable import EclipsePlexClient

struct OfflineScrobbleQueueTests {
    @Test func canFlushRequiresLiveAPI() {
        let offline = PlexServer(name: "X", hostDescription: "offline", accessToken: nil)
        #expect(OfflineScrobbleQueue.canFlush(to: offline) == false)

        let live = PlexServer(name: "Y", hostDescription: "http://127.0.0.1:32400", accessToken: "tok")
        #expect(OfflineScrobbleQueue.canFlush(to: live) == true)
    }
}
