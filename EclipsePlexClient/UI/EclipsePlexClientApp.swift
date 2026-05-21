//
//  EclipsePlexClientApp.swift
//  EclipsePlexClient
//
//  Created by Matt Brown on 5/15/26.
//

import SwiftUI

@main
struct EclipsePlexClientApp: App {
    @StateObject private var downloadManager = OfflineDownloadManager()
    @StateObject private var toastCenter = AppToastCenter()

    var body: some Scene {
        WindowGroup {
            RootShellView()
                .offlineDownloads(downloadManager)
                .environmentObject(toastCenter)
                .appToastOverlay(toastCenter)
        }
#if os(macOS)
        .commands {
            CommandGroup(replacing: .sidebar) {
                Button("Browse") {
                    NotificationCenter.default.post(name: .eclipsePlexOpenBrowseMenu, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
        }
#endif
    }
}

extension Notification.Name {
    static let eclipsePlexOpenBrowseMenu = Notification.Name("eclipsePlexOpenBrowseMenu")
}
