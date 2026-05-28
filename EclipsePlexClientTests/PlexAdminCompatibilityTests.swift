//  PlexAdminCompatibilityTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct PlexAdminCompatibilityTests {
    @Test func notFoundIncludesActionName() {
        let error = PlexAPIError.httpStatus(code: 404, bodySnippet: nil)
        let message = PlexAdminCompatibility.message(for: error, action: "analyze")
        #expect(message.contains("analyze"))
        #expect(message.contains("Plex server"))
    }
}
