//
//  CatalogWatchFilterTests.swift
//  EclipsePlexClientTests
//

import Testing
@testable import EclipsePlexClient

struct CatalogWatchFilterTests {
    @Test func inProgressFilterCaseExists() {
        #expect(CatalogWatchFilter.inProgress.menuTitle == "In progress")
        #expect(CatalogWatchFilter.inProgress.filtersClientSideInProgress)
    }
}
