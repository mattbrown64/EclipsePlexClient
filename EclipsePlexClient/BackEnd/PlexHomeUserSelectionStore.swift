//
//  PlexHomeUserSelectionStore.swift
//  EclipsePlexClient
//

import Foundation

/// Remembers the selected Plex Home user per server (display-only until per-user tokens are wired).
enum PlexHomeUserSelectionStore {
    private static let prefix = "plexHomeUser.selected.v1"

    static func selectedUserID(for serverId: UUID) -> Int? {
        let key = "\(prefix).\(serverId.uuidString)"
        let value = UserDefaults.standard.integer(forKey: key)
        return value > 0 ? value : nil
    }

    static func setSelectedUserID(_ userID: Int?, for serverId: UUID) {
        let key = "\(prefix).\(serverId.uuidString)"
        if let userID, userID > 0 {
            UserDefaults.standard.set(userID, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
