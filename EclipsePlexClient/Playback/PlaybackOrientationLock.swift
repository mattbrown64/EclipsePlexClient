//
//  PlaybackOrientationLock.swift
//  EclipsePlexClient
//

import SwiftUI

#if os(iOS)
import UIKit

/// Restricts interface orientation to landscape while video playback is active (iPhone).
@MainActor
enum PlaybackOrientationLock {
    private(set) static var isPlaybackActive = false
    private(set) static var supportedMask: UIInterfaceOrientationMask = .all

    static var isLockedToLandscape: Bool {
        isPlaybackActive
    }

    static func enterPlayback() {
        isPlaybackActive = true
        supportedMask = [.landscapeLeft, .landscapeRight]
        applyLandscapeGeometry()
    }

    static func exitPlayback() {
        guard isPlaybackActive else { return }
        isPlaybackActive = false
        supportedMask = .all
        // Unlock only — forcing portrait while playback UI is still landscape fails geometry updates.
        UIViewController.attemptRotationToDeviceOrientation()
    }

    private static func applyLandscapeGeometry() {
        guard let scene = foregroundWindowScene else { return }
        if #available(iOS 16.0, *) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { error in
                AppLog.playback("Playback landscape geometry: \(error.localizedDescription)")
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { retryError in
                        AppLog.playback("Playback landscape retry: \(retryError.localizedDescription)")
                    }
                }
            }
        }
        UIViewController.attemptRotationToDeviceOrientation()
    }

    private static var foregroundWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}

#endif
