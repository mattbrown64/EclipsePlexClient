//
//  BrowseKeyboardCapture.swift
//  EclipsePlexClient
//

import SwiftUI

extension Notification.Name {
    /// Posted when E is pressed; `RootShellView` pops navigation or moves focus to the sidebar.
    static let eclipsePlexBrowseBack = Notification.Name("eclipsePlexBrowseBack")
}

// MARK: - Coordinator actions (callable from menu commands without view focus)

extension KeyboardFocusCoordinator {
    func handleArrowUp() {
        guard browseKeyboardCommandsEnabled else { return }
        switch route {
        case .sidebar:
            moveSidebarFocus(by: -1)
        case .homeHubs:
            moveHomeFocus(by: -1)
        case .catalogList, .detailActions, .player:
            moveCatalogFocus(vertical: -1)
        }
    }

    func handleArrowDown() {
        guard browseKeyboardCommandsEnabled else { return }
        switch route {
        case .sidebar:
            moveSidebarFocus(by: 1)
        case .homeHubs:
            moveHomeFocus(by: 1)
        case .catalogList, .detailActions, .player:
            moveCatalogFocus(vertical: 1)
        }
    }

    func handleArrowLeft() {
        guard browseKeyboardCommandsEnabled else { return }
        switch route {
        case .sidebar:
            toggleBrowsePane()
        case .homeHubs:
            moveHomeFocus(by: -1)
        case .catalogList, .detailActions, .player:
            moveCatalogFocus(vertical: 0, horizontal: -1)
        }
    }

    func handleArrowRight() {
        guard browseKeyboardCommandsEnabled else { return }
        switch route {
        case .sidebar:
            if homeItemCount > 0 {
                focusHome()
            } else if catalogItemCount > 0 {
                focusCatalog()
            }
        case .homeHubs:
            moveHomeFocus(by: 1)
        case .catalogList, .detailActions, .player:
            moveCatalogFocus(vertical: 0, horizontal: 1)
        }
    }

    func handleTabKey() {
        guard browseKeyboardCommandsEnabled else { return }
        toggleBrowsePane()
    }

    func handleReturnKey() {
        guard browseKeyboardCommandsEnabled else { return }
        switch route {
        case .sidebar:
            activateSidebarFocus()
        case .homeHubs:
            activateHomeFocus()
        case .catalogList, .detailActions, .player:
            activateCatalogFocus()
        }
    }

    func handleBackKey() {
        guard browseKeyboardCommandsEnabled else { return }
        NotificationCenter.default.post(name: .eclipsePlexBrowseBack, object: nil)
    }

    func activateCatalogFocus() {
        requestCatalogActivate()
    }
}

// MARK: - Hidden shortcuts (letters + fallback when menus unavailable)

struct BrowseKeyboardCaptureView: View {
    @ObservedObject var coordinator: KeyboardFocusCoordinator

    var body: some View {
#if os(iOS) || os(macOS)
        Group {
            arrowCaptureButton { coordinator.handleArrowUp() }
                .keyboardShortcut(.upArrow, modifiers: [])
            arrowCaptureButton { coordinator.handleArrowDown() }
                .keyboardShortcut(.downArrow, modifiers: [])
            arrowCaptureButton { coordinator.handleArrowLeft() }
                .keyboardShortcut(.leftArrow, modifiers: [])
            arrowCaptureButton { coordinator.handleArrowRight() }
                .keyboardShortcut(.rightArrow, modifiers: [])
            arrowCaptureButton { coordinator.handleTabKey() }
                .keyboardShortcut(.tab, modifiers: [])
            arrowCaptureButton { coordinator.handleReturnKey() }
                .keyboardShortcut(.return, modifiers: [])
            arrowCaptureButton { coordinator.handleBackKey() }
                .keyboardShortcut("e", modifiers: [])
            arrowCaptureButton { coordinator.handleBackKey() }
                .keyboardShortcut("e", modifiers: [.shift])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
#else
        EmptyView()
#endif
    }

    private func arrowCaptureButton(action: @escaping () -> Void) -> some View {
        Button("", action: action)
    }
}

#if os(macOS)
/// Menu commands so arrow keys work without clicking into the window first.
struct BrowseKeyboardCommands: Commands {
    @ObservedObject var coordinator: KeyboardFocusCoordinator

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Move Up") { coordinator.handleArrowUp() }
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("Move Down") { coordinator.handleArrowDown() }
                .keyboardShortcut(.downArrow, modifiers: [])
            Button("Move Left") { coordinator.handleArrowLeft() }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Move Right") { coordinator.handleArrowRight() }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Divider()
            Button("Switch Sidebar / Detail") { coordinator.handleTabKey() }
                .keyboardShortcut(.tab, modifiers: [])
            Button("Open Selection") { coordinator.handleReturnKey() }
                .keyboardShortcut(.return, modifiers: [])
            Button("Back") { coordinator.handleBackKey() }
                .keyboardShortcut("e", modifiers: [])
        }
    }
}
#endif
