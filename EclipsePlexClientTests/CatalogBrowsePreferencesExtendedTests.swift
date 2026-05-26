//
//  CatalogBrowsePreferencesExtendedTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct CatalogBrowsePreferencesExtendedTests {
    @Test func viewModeStorageKeyIncludesParent() {
        let serverId = UUID()
        let rootKey = CatalogBrowsePreferences.viewModeStorageKey(
            serverId: serverId,
            libraryId: "lib1",
            parent: .root
        )
        let showKey = CatalogBrowsePreferences.viewModeStorageKey(
            serverId: serverId,
            libraryId: "lib1",
            parent: .show(ratingKey: "show-9")
        )
        #expect(rootKey != showKey)
        #expect(rootKey.contains("lib1"))
    }

    @Test func saveAndLoadViewModeRoundTrip() {
        let serverId = UUID()
        CatalogBrowsePreferences.saveViewMode(.list, serverId: serverId, libraryId: "movies", parent: .root)
        let loaded = CatalogBrowsePreferences.loadViewMode(
            serverId: serverId,
            libraryId: "movies",
            parent: .root
        )
        #expect(loaded == .list)
        let key = CatalogBrowsePreferences.viewModeStorageKey(
            serverId: serverId,
            libraryId: "movies",
            parent: .root
        )
        UserDefaults.standard.removeObject(forKey: key)
    }
}
