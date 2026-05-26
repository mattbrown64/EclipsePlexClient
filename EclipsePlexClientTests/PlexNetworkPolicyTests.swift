import Foundation
import Testing
@testable import EclipsePlexClient

struct PlexNetworkPolicyTests {
    @Test func allowsLANHTTP() throws {
        _ = try PlexNetworkPolicy.validateHostDescription("http://192.168.1.10:32400")
        #expect(PlexNetworkPolicy.isLocalNetworkHost(URL(string: "http://192.168.1.10:32400")!))
    }

    @Test func rejectsRemoteHTTP() {
        #expect(throws: PlexNetworkPolicy.ValidationError.insecureRemoteHTTP) {
            try PlexNetworkPolicy.validateHostDescription("http://plex.example.com:32400")
        }
    }

    @Test func allowsRemoteHTTPS() throws {
        _ = try PlexNetworkPolicy.validateHostDescription("https://plex.example.com:32400")
    }
}
