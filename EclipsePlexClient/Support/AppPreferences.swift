//
//  AppPreferences.swift
//  EclipsePlexClient
//

import Foundation

enum AppPreferences {
    private static let quitWhenClosingKey = "app.quitWhenClosingWindow.v1"
    private static let recentServerIdsKey = "app.recentServerIds.v1"

    /// When true (default), closing the main window quits the app on macOS.
    static var quitWhenClosingWindow: Bool {
        get {
            if UserDefaults.standard.object(forKey: quitWhenClosingKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: quitWhenClosingKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: quitWhenClosingKey) }
    }

    static func recordRecentServer(id: UUID) {
        var ids = recentServerIds().filter { $0 != id }
        ids.insert(id, at: 0)
        let trimmed = Array(ids.prefix(5))
        UserDefaults.standard.set(trimmed.map(\.uuidString), forKey: recentServerIdsKey)
    }

    static func recentServerIds() -> [UUID] {
        guard let raw = UserDefaults.standard.stringArray(forKey: recentServerIdsKey) else { return [] }
        return raw.compactMap(UUID.init(uuidString:))
    }
}
