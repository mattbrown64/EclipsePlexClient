//
//  MacDockMenuProvider.swift
//  EclipsePlexClient
//

#if os(macOS)
import AppKit

@MainActor
enum MacDockMenuProvider {
    static func makeMenu(registry: PlexServerRegistry) -> NSMenu {
        let menu = NSMenu()
        let recent = AppPreferences.recentServerIds()
        let servers = registry.allServers.filter { !$0.isDownloadsServer }

        if !recent.isEmpty {
            for id in recent.prefix(3) {
                guard let server = servers.first(where: { $0.id == id }) else { continue }
                let item = NSMenuItem(title: server.name, action: #selector(MacDockActions.openServer(_:)), keyEquivalent: "")
                item.representedObject = id.uuidString
                item.target = MacDockActions.shared
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        let openItem = NSMenuItem(title: "Open EclipsePlex", action: #selector(MacDockActions.activateApp), keyEquivalent: "")
        openItem.target = MacDockActions.shared
        menu.addItem(openItem)

        let quitItem = NSMenuItem(title: "Quit EclipsePlex", action: #selector(MacDockActions.quitApp), keyEquivalent: "q")
        quitItem.target = MacDockActions.shared
        menu.addItem(quitItem)
        return menu
    }
}

@MainActor
final class MacDockActions: NSObject {
    static let shared = MacDockActions()

    @objc func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            break
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    @objc func openServer(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let id = UUID(uuidString: raw)
        else { return }
        UserDefaults.standard.set(id.uuidString, forKey: "selectedPlexServerId")
        activateApp()
        NotificationCenter.default.post(name: .eclipsePlexOpenBrowseMenu, object: nil)
    }
}
#endif
