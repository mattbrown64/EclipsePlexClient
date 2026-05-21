import Foundation

/// Persists playback position per Plex item for resume.
enum PlaybackPositionStore {
    private static let defaults = UserDefaults.standard
    private static let keyPrefix = "playbackPositionMs.v1"

    static func load(serverId: UUID, ratingKey: String) -> Int? {
        let ms = defaults.integer(forKey: storageKey(serverId: serverId, ratingKey: ratingKey))
        return ms > 0 ? ms : nil
    }

    static func save(serverId: UUID, ratingKey: String, positionMs: Int) {
        let key = storageKey(serverId: serverId, ratingKey: ratingKey)
        if positionMs <= 0 {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(positionMs, forKey: key)
        }
    }

    static func clear(serverId: UUID, ratingKey: String) {
        defaults.removeObject(forKey: storageKey(serverId: serverId, ratingKey: ratingKey))
    }

    private static func storageKey(serverId: UUID, ratingKey: String) -> String {
        "\(keyPrefix).\(serverId.uuidString).\(ratingKey)"
    }
}
