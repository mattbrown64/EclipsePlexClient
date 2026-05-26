//
//  KeyboardFocusCoordinator.swift
//  EclipsePlexClient
//

import Combine
import SwiftUI

/// Documented focus routes for keyboard navigation (Apple TV prep).
enum AppFocusRoute: String, Sendable {
    case sidebar
    case homeHubs
    case catalogList
    case detailActions
    case player
}

/// One selectable row in the browse sidebar (keyboard focus).
struct SidebarFocusRow: Identifiable {
    let id: String
    let perform: @MainActor () -> Void
}

/// Shared keyboard routing state for browse UI.
@MainActor
final class KeyboardFocusCoordinator: ObservableObject {
    @Published var route: AppFocusRoute = .sidebar
    @Published var sidebarFocusedIndex: Int = 0
    @Published var catalogFocusedIndex: Int = 0
    @Published var homeFocusedIndex: Int = 0
    @Published private(set) var sidebarRows: [SidebarFocusRow] = []
    @Published private(set) var homeItems: [HomeFocusItem] = []
    @Published var catalogItemCount: Int = 0

    var homeItemCount: Int { homeItems.count }
    @Published private(set) var catalogUsesGrid: Bool = false
    @Published private(set) var catalogColumnCount: Int = 1

    var browseKeyboardCommandsEnabled: Bool = true

    private(set) var catalogActivateHandlerOwnerID: String?
    @Published private(set) var catalogActivateRequestID: UInt = 0

    func registerCatalogActivateHandler(id: String) {
        catalogActivateHandlerOwnerID = id
    }

    func unregisterCatalogActivateHandler(id: String) {
        guard catalogActivateHandlerOwnerID == id else { return }
        catalogActivateHandlerOwnerID = nil
    }

    func requestCatalogActivate() {
        guard catalogActivateHandlerOwnerID != nil else { return }
        catalogActivateRequestID += 1
    }

    func setSidebarRows(_ rows: [SidebarFocusRow]) {
        sidebarRows = rows
        clampSidebarIndex()
    }

    func setCatalogItemCount(_ count: Int) {
        catalogItemCount = count
        clampCatalogIndex()
    }

    func setCatalogLayout(isGrid: Bool, columnCount: Int) {
        catalogUsesGrid = isGrid
        catalogColumnCount = max(1, columnCount)
        clampCatalogIndex()
    }

    /// Apply item count, grid layout, and the activate-handler ownership in
    /// a single MainActor turn. Each property is `@Published`, so writing them
    /// individually used to publish 3 times per `syncCatalogFocusState()` call
    /// — and that helper runs on every reload / sort / filter / view-mode
    /// change. Batching reduces it to one ObservableObject change per call.
    func updateCatalogLayout(itemCount: Int, isGrid: Bool, columnCount: Int, handlerID: String) {
        catalogItemCount = itemCount
        catalogUsesGrid = isGrid
        catalogColumnCount = max(1, columnCount)
        catalogActivateHandlerOwnerID = handlerID
        clampCatalogIndex()
    }

    func focusSidebar() {
        route = .sidebar
    }

    func focusCatalog() {
        route = .catalogList
    }

    func focusHome() {
        route = .homeHubs
    }

    func clearHomeItems() {
        homeItems = []
        clampHomeIndex()
    }

    func setHomeItems(_ items: [HomeFocusItem]) {
        homeItems = items
        clampHomeIndex()
    }

    func moveHomeFocus(by delta: Int) {
        guard !homeItems.isEmpty else { return }
        route = .homeHubs
        let count = homeItems.count
        homeFocusedIndex = max(0, min(count - 1, homeFocusedIndex + delta))
    }

    func activateHomeFocus() {
        guard homeItems.indices.contains(homeFocusedIndex) else { return }
        homeItems[homeFocusedIndex].activate()
    }

    func homeFocusActive(forIndex index: Int) -> Bool {
        route == .homeHubs && homeFocusedIndex == index
    }

    func toggleBrowsePane() {
        switch route {
        case .sidebar:
            if homeItemCount > 0 {
                route = .homeHubs
            } else if catalogItemCount > 0 {
                route = .catalogList
            }
        case .homeHubs, .catalogList, .detailActions, .player:
            route = .sidebar
        }
    }

    func moveSidebarFocus(by delta: Int) {
        guard !sidebarRows.isEmpty else { return }
        route = .sidebar
        let count = sidebarRows.count
        sidebarFocusedIndex = (sidebarFocusedIndex + delta + count * 8) % count
    }

    func moveCatalogFocus(vertical delta: Int, horizontal horizontalDelta: Int = 0) {
        guard catalogItemCount > 0 else { return }
        route = .catalogList
        let count = catalogItemCount
        var index = catalogFocusedIndex
        if catalogUsesGrid, catalogColumnCount > 1 {
            if horizontalDelta != 0 {
                index += horizontalDelta
            } else if delta != 0 {
                index += delta * catalogColumnCount
            }
        } else {
            index += delta != 0 ? delta : horizontalDelta
        }
        catalogFocusedIndex = max(0, min(count - 1, index))
    }

    func activateSidebarFocus() {
        guard sidebarRows.indices.contains(sidebarFocusedIndex) else { return }
        sidebarRows[sidebarFocusedIndex].perform()
    }

    func catalogFocusActive(forIndex index: Int) -> Bool {
        route == .catalogList && catalogFocusedIndex == index
    }

    private func clampSidebarIndex() {
        guard !sidebarRows.isEmpty else {
            sidebarFocusedIndex = 0
            return
        }
        sidebarFocusedIndex = min(sidebarFocusedIndex, sidebarRows.count - 1)
    }

    private func clampCatalogIndex() {
        guard catalogItemCount > 0 else {
            catalogFocusedIndex = 0
            return
        }
        catalogFocusedIndex = min(catalogFocusedIndex, catalogItemCount - 1)
    }

    private func clampHomeIndex() {
        guard !homeItems.isEmpty else {
            homeFocusedIndex = 0
            return
        }
        homeFocusedIndex = min(homeFocusedIndex, homeItems.count - 1)
    }
}

enum KeyboardFocusIndex {
    nonisolated static func clamped(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return max(0, min(count - 1, index))
    }
}

