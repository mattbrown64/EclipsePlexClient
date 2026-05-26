//
//  CrashReporter.swift
//  EclipsePlexClient
//

import Foundation

private func eclipsePlexUncaughtExceptionHandler(_ exception: NSException) {
    CrashReporter.recordUncaught(exception)
}

/// Records recent errors and optional crash metadata for diagnostics. Wire Sentry DSN via `SentryDSN` in Info.plist when ready.
enum CrashReporter {
    private static let recentErrorsKey = "crashReporter.recentErrors.v1"
    private static let maxRecent = 20

    static func start() {
        NSSetUncaughtExceptionHandler(eclipsePlexUncaughtExceptionHandler)
        AppLog.ui("CrashReporter started")
    }

    static func recordUncaught(_ exception: NSException) {
        record(
            message: "Uncaught \(exception.name.rawValue): \(exception.reason ?? "unknown")",
            category: "crash"
        )
    }

    static var sentryDSN: String? {
        Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String
    }

    static func record(message: String, category: String = "error") {
        let sanitized = AppLog.redact(message)
        let entry = "[\(ISO8601DateFormatter().string(from: Date()))] [\(category)] \(sanitized)"
        var lines = UserDefaults.standard.stringArray(forKey: recentErrorsKey) ?? []
        lines.insert(entry, at: 0)
        if lines.count > maxRecent {
            lines = Array(lines.prefix(maxRecent))
        }
        UserDefaults.standard.set(lines, forKey: recentErrorsKey)
        #if DEBUG
        AppLog.ui("CrashReporter: \(entry)")
        #endif
    }

    static func recentErrorsForDiagnostics() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentErrorsKey) ?? []
    }

    static func clearRecentErrors() {
        UserDefaults.standard.removeObject(forKey: recentErrorsKey)
    }
}
