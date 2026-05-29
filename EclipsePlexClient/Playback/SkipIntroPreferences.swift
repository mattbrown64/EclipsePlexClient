//
//  SkipIntroPreferences.swift
//  EclipsePlexClient
//

import Foundation

enum SkipIntroPreferences {
    private static let perShowPrefix = "skipIntro.always.v1"

    static func alwaysSkip(for serverId: UUID, showRatingKey: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(serverId: serverId, showRatingKey: showRatingKey))
    }

    static func setAlwaysSkip(_ value: Bool, serverId: UUID, showRatingKey: String) {
        let k = key(serverId: serverId, showRatingKey: showRatingKey)
        if value {
            UserDefaults.standard.set(true, forKey: k)
        } else {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }

    static func resetAllShowPreferences() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(perShowPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private static func key(serverId: UUID, showRatingKey: String) -> String {
        "\(perShowPrefix).\(serverId.uuidString).\(showRatingKey)"
    }
}
