//
//  AppDiagnostics.swift
//  EclipsePlexClient
//

import Foundation

#if os(iOS) || os(tvOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum AppDiagnostics {
    static func exportText(
        registry: PlexServerRegistry,
        downloadManager: OfflineDownloadManager
    ) -> String {
        var lines: [String] = [
            "EclipsePlex \(AppVersion.displayString)",
            "Bundle: \(Bundle.main.bundleIdentifier ?? "unknown")",
            "Platform: \(platformDescription)",
            "OS: \(osVersion)",
            "Plex.tv signed in: \(registry.plexAccountAuthToken != nil)",
            "Servers: \(registry.allServers.count)",
        ]

        for server in registry.allServers {
            let reachable = registry.serverReachable[server.id].map { $0 ? "up" : "down" } ?? "unknown"
            let host = server.hostDescription
            lines.append("- \(server.name): \(reachable) · \(host)")
        }

        let active = downloadManager.records.filter { $0.state == .downloading || $0.state == .pending }
        let failed = downloadManager.records.filter { $0.state == .failed }
        lines.append("Downloads: \(downloadManager.records.count) total, \(active.count) active, \(failed.count) failed")
        lines.append("Storage used: \(ByteCountFormatter.string(fromByteCount: downloadManager.totalDownloadedBytes, countStyle: .file))")

        let recent = CrashReporter.recentErrorsForDiagnostics()
        if !recent.isEmpty {
            lines.append("Recent errors:")
            lines.append(contentsOf: recent.prefix(10))
        }

        if let dsn = CrashReporter.sentryDSN, !dsn.isEmpty {
            lines.append("Crash reporting: configured")
        } else {
            lines.append("Crash reporting: local buffer only (set SentryDSN in Info.plist to enable remote)")
        }

        return lines.joined(separator: "\n")
    }

    private static var platformDescription: String {
        #if os(iOS)
        return "iOS \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return "unknown"
        #endif
    }

    private static var osVersion: String {
        #if os(iOS) || os(tvOS)
        return UIDevice.current.systemVersion
        #elseif os(macOS)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #else
        return "unknown"
        #endif
    }
}
