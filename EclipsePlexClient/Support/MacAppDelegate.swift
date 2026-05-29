//
//  MacAppDelegate.swift
//  EclipsePlexClient
//

#if os(macOS)
import AppKit

/// Makes the red traffic-light close button quit the app (not leave a headless process).
@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    static weak var registry: PlexServerRegistry?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let registry = Self.registry else { return nil }
        return MacDockMenuProvider.makeMenu(registry: registry)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard AppPreferences.quitWhenClosingWindow else { return }
        guard let window = notification.object as? NSWindow else { return }
        guard shouldQuitWhenClosing(window) else { return }
        NSApp.terminate(nil)
    }

    /// Quit on the main window only — not sheets, popovers, or auxiliary panels.
    private func shouldQuitWhenClosing(_ window: NSWindow) -> Bool {
        if window.isSheet { return false }
        if window.level != .normal { return false }
        if window.isKind(of: NSPanel.self) { return false }
        return true
    }
}
#endif
