//
//  PlexAdminActionLog.swift
//  EclipsePlexClient
//

import Foundation

/// Lightweight audit trail for server-admin actions (diagnostics / support).
enum PlexAdminActionLog {
    static func record(
        serverName: String,
        action: String,
        success: Bool,
        detail: String? = nil
    ) {
        let status = success ? "ok" : "failed"
        var message = "Admin[\(serverName)] \(action): \(status)"
        if let detail, !detail.isEmpty {
            message += " — \(detail)"
        }
        AppLog.network(message)
    }
}
