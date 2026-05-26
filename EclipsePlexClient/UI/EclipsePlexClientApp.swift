//
//  EclipsePlexClientApp.swift
//  EclipsePlexClient
//
//  Created by Matt Brown on 5/15/26.
//

import SwiftUI

@main
struct EclipsePlexClientApp: App {
#if os(iOS)
    @UIApplicationDelegateAdaptor(OfflineDownloadAppDelegate.self) private var appDelegate
#endif
    @StateObject private var downloadManager = OfflineDownloadManager()

    init() {
        CrashReporter.start()
    }
    @StateObject private var toastCenter = AppToastCenter()
    @StateObject private var focusCoordinator = KeyboardFocusCoordinator()
    @StateObject private var playbackQueue = PlaybackQueueManager()

    var body: some Scene {
        WindowGroup {
            RootShellView()
                .offlineDownloads(downloadManager)
                .environmentObject(toastCenter)
                .environmentObject(focusCoordinator)
                .environmentObject(playbackQueue)
                .appToastOverlay(toastCenter)
#if os(iOS) || os(macOS)
                .background {
                    BrowseKeyboardCaptureView(coordinator: focusCoordinator)
                }
#endif
        }
#if os(macOS)
        .commands {
            CommandGroup(replacing: .sidebar) {
                Button("Browse") {
                    NotificationCenter.default.post(name: .eclipsePlexOpenBrowseMenu, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
            BrowseKeyboardCommands(coordinator: focusCoordinator)
            CommandGroup(after: .sidebar) {
                Button("Search Server") {
                    NotificationCenter.default.post(name: .eclipsePlexOpenSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                Button("Refresh Libraries") {
                    NotificationCenter.default.post(name: .eclipsePlexRefreshLibraries, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
#endif
    }
}

extension Notification.Name {
    static let eclipsePlexOpenBrowseMenu = Notification.Name("eclipsePlexOpenBrowseMenu")
}
