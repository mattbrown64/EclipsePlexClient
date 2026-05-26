//
//  AppVersion.swift
//  EclipsePlexClient
//

import Foundation

/// Single source for marketing version and build number (from Info.plist / Xcode settings).
enum AppVersion {
    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var displayString: String {
        "\(marketingVersion) (\(buildNumber))"
    }
}
