//
//  OfflineDownloadPreferences.swift
//  EclipsePlexClient
//

import Foundation

enum OfflineDownloadPreferences {
    private static let wifiOnlyKey = "offlineDownloads.wifiOnly.v1"
    private static let storageCapGBKey = "offlineDownloads.storageCapGB.v1"
    private static let defaultQualityKey = "offlineDownloads.defaultQuality.v1"
    private static let pruneWatchedKey = "offlineDownloads.pruneWatched.v1"
    private static let notificationsEnabledKey = "offlineDownloads.notificationsEnabled.v1"
    private static let notifyOnSuccessKey = "offlineDownloads.notifyOnSuccess.v1"
    private static let notifyOnFailureKey = "offlineDownloads.notifyOnFailure.v1"

    static let defaultStorageCapGB = 50

    static var wifiOnly: Bool {
        get {
            if UserDefaults.standard.object(forKey: wifiOnlyKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: wifiOnlyKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: wifiOnlyKey) }
    }

    static var storageCapGB: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: storageCapGBKey)
            return value > 0 ? value : defaultStorageCapGB
        }
        set { UserDefaults.standard.set(max(1, newValue), forKey: storageCapGBKey) }
    }

    static var defaultQuality: PlaybackVideoResolution {
        get {
            if let raw = UserDefaults.standard.string(forKey: defaultQualityKey),
               let value = PlaybackVideoResolution(rawValue: raw) {
                return value
            }
            return .p720
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultQualityKey) }
    }

    /// When over the storage cap, remove completed downloads marked watched on Plex first.
    static var pruneWatchedWhenOverCap: Bool {
        get {
            if UserDefaults.standard.object(forKey: pruneWatchedKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: pruneWatchedKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: pruneWatchedKey) }
    }

    static var storageCapBytes: Int64 {
        Int64(storageCapGB) * 1_024 * 1_024 * 1_024
    }

    /// Master switch for download notifications (where supported).
    static var notificationsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: notificationsEnabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: notificationsEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: notificationsEnabledKey) }
    }

    static var notifyOnSuccess: Bool {
        get {
            if UserDefaults.standard.object(forKey: notifyOnSuccessKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: notifyOnSuccessKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: notifyOnSuccessKey) }
    }

    static var notifyOnFailure: Bool {
        get {
            if UserDefaults.standard.object(forKey: notifyOnFailureKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: notifyOnFailureKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: notifyOnFailureKey) }
    }
}
