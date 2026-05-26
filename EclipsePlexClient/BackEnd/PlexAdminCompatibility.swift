//
//  PlexAdminCompatibility.swift
//  EclipsePlexClient
//

import Foundation

/// Maps admin API failures to actionable copy when a Plex Media Server lacks an endpoint.
enum PlexAdminCompatibility {
    static func message(for error: Error, action: String) -> String {
        if let plex = error as? PlexAPIError,
           case .httpStatus(let code, _) = plex,
           code == 404 {
            return "This Plex server does not support \(action). Update Plex Media Server or use the Plex web app."
        }
        return PlexAPIError.from(error)
    }
}
