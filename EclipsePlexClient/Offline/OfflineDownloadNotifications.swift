//
//  OfflineDownloadNotifications.swift
//  EclipsePlexClient
//

import Foundation

#if os(iOS)
import UserNotifications

enum OfflineDownloadNotifications {
    static func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    static func requestAuthorizationIfNeeded() async -> Bool {
        let status = await authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    static func scheduleCompletionNotification(title: String) async {
        guard OfflineDownloadPreferences.notificationsEnabled else { return }
        guard OfflineDownloadPreferences.notifyOnSuccess else { return }
        guard await requestAuthorizationIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Download completed"
        content.body = title
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "offline-download-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func scheduleFailureNotification(title: String, message: String) async {
        guard OfflineDownloadPreferences.notificationsEnabled else { return }
        guard OfflineDownloadPreferences.notifyOnFailure else { return }
        guard await requestAuthorizationIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Download failed"
        content.body = "\(title): \(message)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "offline-download-failed-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
#else
enum OfflineDownloadNotifications {
    static func requestAuthorizationIfNeeded() async -> Bool { false }
    static func scheduleCompletionNotification(title _: String) async {}
    static func scheduleFailureNotification(title _: String, message _: String) async {}
}
#endif
