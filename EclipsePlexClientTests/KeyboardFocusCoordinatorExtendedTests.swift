//
//  KeyboardFocusCoordinatorExtendedTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

@MainActor
struct KeyboardFocusCoordinatorExtendedTests {
    @Test func catalogListModeMovesOneAtATime() {
        let coordinator = KeyboardFocusCoordinator()
        coordinator.setCatalogLayout(isGrid: false, columnCount: 1)
        coordinator.setCatalogItemCount(5)
        coordinator.catalogFocusedIndex = 2
        coordinator.moveCatalogFocus(vertical: 1)
        #expect(coordinator.catalogFocusedIndex == 3)
        coordinator.moveCatalogFocus(vertical: 0, horizontal: -1)
        #expect(coordinator.catalogFocusedIndex == 2)
    }

    @Test func catalogGridClampsAtEdges() {
        let coordinator = KeyboardFocusCoordinator()
        coordinator.setCatalogLayout(isGrid: true, columnCount: 3)
        coordinator.setCatalogItemCount(4)
        coordinator.catalogFocusedIndex = 0
        coordinator.moveCatalogFocus(vertical: -1)
        #expect(coordinator.catalogFocusedIndex == 0)
        coordinator.catalogFocusedIndex = 3
        coordinator.moveCatalogFocus(vertical: 1)
        #expect(coordinator.catalogFocusedIndex == 3)
    }

    @Test func activateSidebarInvokesClosure() {
        let coordinator = KeyboardFocusCoordinator()
        var activatedID: String?
        coordinator.setSidebarRows([
            SidebarFocusRow(id: "first") { activatedID = "first" },
            SidebarFocusRow(id: "second") { activatedID = "second" },
        ])
        coordinator.sidebarFocusedIndex = 1
        coordinator.activateSidebarFocus()
        #expect(activatedID == "second")
    }

    @Test func catalogActivateRequestIncrements() {
        let coordinator = KeyboardFocusCoordinator()
        coordinator.registerCatalogActivateHandler(id: "owner-a")
        let before = coordinator.catalogActivateRequestID
        coordinator.requestCatalogActivate()
        #expect(coordinator.catalogActivateRequestID == before + 1)
        coordinator.unregisterCatalogActivateHandler(id: "owner-a")
        coordinator.requestCatalogActivate()
        #expect(coordinator.catalogActivateRequestID == before + 1)
    }

    @Test func clearHomeItemsResetsCount() {
        let coordinator = KeyboardFocusCoordinator()
        coordinator.setHomeItems([HomeFocusItem(id: "a") {}])
        coordinator.homeFocusedIndex = 0
        coordinator.clearHomeItems()
        #expect(coordinator.homeItemCount == 0)
        coordinator.toggleBrowsePane()
        #expect(coordinator.route == .sidebar)
    }

    @Test func handleArrowRightFromSidebarFocusesHome() {
        let coordinator = KeyboardFocusCoordinator()
        coordinator.setHomeItems([HomeFocusItem(id: "h") {}])
        coordinator.focusSidebar()
        coordinator.handleArrowRight()
        #expect(coordinator.route == .homeHubs)
    }

    @Test func handleArrowRightFromSidebarFocusesCatalogWhenNoHome() {
        let coordinator = KeyboardFocusCoordinator()
        coordinator.setCatalogItemCount(2)
        coordinator.focusSidebar()
        coordinator.handleArrowRight()
        #expect(coordinator.route == .catalogList)
    }

    @Test func handleArrowLeftFromHomeMovesWithinShelf() {
        let coordinator = KeyboardFocusCoordinator()
        coordinator.setHomeItems([
            HomeFocusItem(id: "0") {},
            HomeFocusItem(id: "1") {},
        ])
        coordinator.focusHome()
        coordinator.homeFocusedIndex = 1
        coordinator.handleArrowLeft()
        #expect(coordinator.homeFocusedIndex == 0)
    }

    @Test func catalogFocusActiveRequiresRoute() {
        let coordinator = KeyboardFocusCoordinator()
        coordinator.setCatalogItemCount(3)
        coordinator.catalogFocusedIndex = 1
        coordinator.focusSidebar()
        #expect(!coordinator.catalogFocusActive(forIndex: 1))
        coordinator.focusCatalog()
        #expect(coordinator.catalogFocusActive(forIndex: 1))
    }
}

struct KeyboardFocusIndexTests {
    @Test func clampedWithinRange() {
        #expect(KeyboardFocusIndex.clamped(5, count: 3) == 2)
        #expect(KeyboardFocusIndex.clamped(-2, count: 3) == 0)
        #expect(KeyboardFocusIndex.clamped(1, count: 0) == 0)
    }
}
