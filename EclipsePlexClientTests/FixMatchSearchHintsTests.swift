//  FixMatchSearchHintsTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct FixMatchSearchHintsTests {
    @Test func trimsOptionalFields() {
        let hints = FixMatchSearchHints(
            title: "  Fight Club  ",
            year: 1999,
            showTitle: " ",
            seasonTitle: " Season 1 ",
            manual: true
        )
        #expect(hints.trimmedTitle == "Fight Club")
        #expect(hints.trimmedShowTitle == nil)
        #expect(hints.trimmedSeasonTitle == "Season 1")
    }
}
