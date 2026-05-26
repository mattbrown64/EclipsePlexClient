import Foundation
import Testing
@testable import EclipsePlexClient

@MainActor
struct PlexServerRegistryTests {
    @Test func userAddedServerRoundTrip() {
        let registry = PlexServerRegistry()
        let server = PlexServer(name: "Test", hostDescription: "http://localhost:32400", accessToken: "abc")
        registry.addCustomServer(server)
        #expect(registry.isUserAddedServer(id: server.id))
        #expect(registry.allServers.contains { $0.id == server.id })
        registry.removeCustomServer(id: server.id)
        #expect(!registry.isUserAddedServer(id: server.id))
    }
}
