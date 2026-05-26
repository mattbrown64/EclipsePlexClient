//
//  KeyboardShortcutCatalog.swift
//  EclipsePlexClient
//

import SwiftUI

struct KeyboardShortcutEntry: Identifiable {
    let id: String
    let action: String
    let keys: String
}

struct KeyboardShortcutSection: Identifiable {
    let id: String
    let title: String
    let entries: [KeyboardShortcutEntry]
}

enum KeyboardShortcutCatalog {
    static var sections: [KeyboardShortcutSection] {
        #if os(macOS)
        macSections
        #elseif os(tvOS)
        tvOSSections
        #else
        iosSections
        #endif
    }

    private static var macSections: [KeyboardShortcutSection] {
        [
            KeyboardShortcutSection(
                id: "browse",
                title: "Browse",
                entries: [
                    KeyboardShortcutEntry(id: "openBrowse", action: "Open browse menu", keys: "⌘⇧B"),
                    KeyboardShortcutEntry(id: "search", action: "Search Plex server", keys: "⌘F"),
                    KeyboardShortcutEntry(id: "refresh", action: "Refresh libraries", keys: "⌘R"),
                    KeyboardShortcutEntry(id: "upDown", action: "Move focus in sidebar, home hubs, or catalog", keys: "↑ ↓"),
                    KeyboardShortcutEntry(id: "leftRight", action: "Home hubs / catalog grid; sidebar → detail", keys: "← →"),
                    KeyboardShortcutEntry(id: "tab", action: "Switch sidebar ↔ detail", keys: "Tab"),
                    KeyboardShortcutEntry(id: "return", action: "Open selected item", keys: "Return"),
                    KeyboardShortcutEntry(id: "back", action: "Back one screen", keys: "E"),
                    KeyboardShortcutEntry(id: "watch", action: "Watch (detail screen)", keys: "W"),
                    KeyboardShortcutEntry(id: "resume", action: "Resume (detail screen)", keys: "R"),
                ]
            ),
            KeyboardShortcutSection(
                id: "playback",
                title: "Playback",
                entries: [
                    KeyboardShortcutEntry(id: "playPause", action: "Play / pause", keys: "Space"),
                    KeyboardShortcutEntry(id: "exit", action: "Exit player", keys: "Esc"),
                    KeyboardShortcutEntry(id: "next", action: "Next episode", keys: "N"),
                    KeyboardShortcutEntry(id: "prev", action: "Previous episode", keys: "P"),
                    KeyboardShortcutEntry(id: "back10", action: "Back 10 seconds", keys: ","),
                    KeyboardShortcutEntry(id: "fwd10", action: "Forward 10 seconds", keys: "."),
                ]
            ),
            KeyboardShortcutSection(
                id: "tips",
                title: "Tips",
                entries: [
                    KeyboardShortcutEntry(
                        id: "focus",
                        action: "Open Browse (⌘⇧B), use ↑↓ on Home or libraries, → or Tab for hubs/catalog, ⌘F to search",
                        keys: "—"
                    ),
                ]
            ),
        ]
    }

    private static var tvOSSections: [KeyboardShortcutSection] {
        [
            KeyboardShortcutSection(
                id: "browse",
                title: "Browse (Siri Remote)",
                entries: [
                    KeyboardShortcutEntry(id: "move", action: "Move focus between items", keys: "Swipe"),
                    KeyboardShortcutEntry(id: "select", action: "Open selection / play", keys: "Select"),
                    KeyboardShortcutEntry(id: "menu", action: "Back one screen", keys: "Menu"),
                    KeyboardShortcutEntry(id: "sidebar", action: "Browse menu (sources & libraries)", keys: "Browse toolbar"),
                ]
            ),
            KeyboardShortcutSection(
                id: "playback",
                title: "Playback",
                entries: [
                    KeyboardShortcutEntry(id: "playPause", action: "Play / pause", keys: "Select"),
                    KeyboardShortcutEntry(id: "scrub", action: "Skip ±10 seconds", keys: "◀ ▶"),
                    KeyboardShortcutEntry(id: "exit", action: "Exit player", keys: "Menu"),
                ]
            ),
        ]
    }

    private static var iosSections: [KeyboardShortcutSection] {
        [
            KeyboardShortcutSection(
                id: "browse",
                title: "Browse",
                entries: [
                    KeyboardShortcutEntry(
                        id: "openBrowse",
                        action: "Open browse (sidebar button or sheet)",
                        keys: "—"
                    ),
                    KeyboardShortcutEntry(
                        id: "upDown",
                        action: "Move focus (hardware keyboard)",
                        keys: "↑ ↓"
                    ),
                    KeyboardShortcutEntry(
                        id: "leftRight",
                        action: "Catalog grid sideways; sidebar ↔ catalog",
                        keys: "← →"
                    ),
                    KeyboardShortcutEntry(id: "tab", action: "Switch sidebar ↔ catalog", keys: "Tab"),
                    KeyboardShortcutEntry(id: "return", action: "Open selected item", keys: "Return"),
                    KeyboardShortcutEntry(id: "back", action: "Back one screen", keys: "E"),
                    KeyboardShortcutEntry(id: "watch", action: "Watch (detail)", keys: "W"),
                    KeyboardShortcutEntry(id: "resume", action: "Resume (detail)", keys: "R"),
                ]
            ),
            KeyboardShortcutSection(
                id: "playback",
                title: "Playback",
                entries: [
                    KeyboardShortcutEntry(id: "playPause", action: "Play / pause", keys: "Space"),
                    KeyboardShortcutEntry(id: "exit", action: "Exit player", keys: "Esc"),
                    KeyboardShortcutEntry(id: "next", action: "Next episode", keys: "N"),
                    KeyboardShortcutEntry(id: "prev", action: "Previous episode", keys: "P"),
                    KeyboardShortcutEntry(id: "back10", action: "Back 10 seconds", keys: ","),
                    KeyboardShortcutEntry(id: "fwd10", action: "Forward 10 seconds", keys: "."),
                ]
            ),
            KeyboardShortcutSection(
                id: "tips",
                title: "Tips",
                entries: [
                    KeyboardShortcutEntry(
                        id: "ipad",
                        action: "On iPad, attach a Magic Keyboard for the same shortcuts as Mac",
                        keys: "—"
                    ),
                    KeyboardShortcutEntry(
                        id: "iphone",
                        action: "On iPhone, use an external keyboard or the on-screen keyboard where supported",
                        keys: "—"
                    ),
                ]
            ),
        ]
    }
}
