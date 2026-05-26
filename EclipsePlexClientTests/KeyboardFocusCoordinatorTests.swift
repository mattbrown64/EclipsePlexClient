//
//  KeyboardFocusCoordinatorTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

@MainActor
struct KeyboardFocusCoordinatorTests {
    @Test func sidebarFocusWraps() {
        let coordinator = KeyboardFocusCoordinator()
        coordinator.setSidebarRows([
            SidebarFocusRow(id: "a") {},
            SidebarFocusRow(id: "b") {},
            SidebarFocusRow(id: "c") {},
        ])
        coordinator.sidebarFocusedIndex = 0
        coordinator.moveSidebarFocus(by: -1)
        #expect(coordinator.sidebarFocusedIndex == 2)
        coordinator.moveSidebarFocus(by: 1)
        #expect(coordinator.sidebarFocusedIndex == 0)
    }

    @Test func catalogGridMovesByColumn() {
        let coordinator = KeyboardFocusCoordinator()
        coordinator.setCatalogLayout(isGrid: true, columnCount: 4)
        coordinator.setCatalogItemCount(10)
        coordinator.catalogFocusedIndex = 0
        coordinator.moveCatalogFocus(vertical: 0, horizontal: 1)
        #expect(coordinator.catalogFocusedIndex == 1)
        coordinator.moveCatalogFocus(vertical: 1)
        #expect(coordinator.catalogFocusedIndex == 5)
        coordinator.moveCatalogFocus(vertical: -1)
        #expect(coordinator.catalogFocusedIndex == 1)
    }

    @Test func homeFocusClamps() {
        let coordinator = KeyboardFocusCoordinator()
        var activated = false
        coordinator.setHomeItems([
            HomeFocusItem(id: "one") { activated = true },
            HomeFocusItem(id: "two") {},
        ])
        coordinator.homeFocusedIndex = 1
        coordinator.moveHomeFocus(by: 10)
        #expect(coordinator.homeFocusedIndex == 1)
        coordinator.homeFocusedIndex = 0
        coordinator.activateHomeFocus()
        #expect(activated)
    }

    @Test func togglePanePrefersHomeWhenAvailable() {
        let coordinator = KeyboardFocusCoordinator()
        coordinator.setHomeItems([HomeFocusItem(id: "x") {}])
        coordinator.focusSidebar()
        coordinator.toggleBrowsePane()
        #expect(coordinator.route == .homeHubs)
        coordinator.toggleBrowsePane()
        #expect(coordinator.route == .sidebar)
    }

    @Test func togglePaneUsesCatalogWhenNoHome() {
        let coordinator = KeyboardFocusCoordinator()
        coordinator.setCatalogItemCount(3)
        coordinator.focusSidebar()
        coordinator.toggleBrowsePane()
        #expect(coordinator.route == .catalogList)
    }
}

struct CatalogGridLayoutTests {
    @Test func columnCountFromWidth() {
        #expect(CatalogListView.gridColumnCount(forWidth: 0) >= 1)
        #expect(CatalogListView.gridColumnCount(forWidth: 400) >= 2)
        #expect(CatalogListView.gridColumnCount(forWidth: 1400) >= 6)
    }

    @Test func columnCountIncreasesWithWidth() {
        let narrow = CatalogListView.gridColumnCount(forWidth: 320)
        let wide = CatalogListView.gridColumnCount(forWidth: 1200)
        #expect(wide > narrow)
    }
}
