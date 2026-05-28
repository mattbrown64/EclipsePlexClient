//
//  OfflineDownloadBackgroundSession.swift
//  EclipsePlexClient
//

import Foundation

#if os(iOS)
import UIKit

enum OfflineDownloadBackgroundSession {
    static let identifier = "com.eclipseplex.offline-downloads"

    static var backgroundCompletionHandler: (() -> Void)?

    static func makeConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return config
    }

    /// Re-attach to an in-flight background session after relaunch.
    static func reconnectSharedSession(delegate: URLSessionDownloadDelegate) -> URLSession {
        URLSession(configuration: makeConfiguration(), delegate: delegate, delegateQueue: nil)
    }
}

final class OfflineDownloadAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == OfflineDownloadBackgroundSession.identifier else {
            completionHandler()
            return
        }
        OfflineDownloadBackgroundSession.backgroundCompletionHandler = completionHandler
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        if PlaybackOrientationLock.isLockedToLandscape {
            return PlaybackOrientationLock.supportedMask
        }
        return .all
    }
}
#endif
