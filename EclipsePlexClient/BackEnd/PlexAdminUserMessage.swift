//
//  PlexAdminUserMessage.swift
//  EclipsePlexClient
//

import Foundation

extension PlexAPIError {
    /// User-facing copy for server-management flows.
    var adminUserMessage: String {
        switch self {
        case .serverNotConfiguredForLiveAPI:
            return "Add a reachable server URL and Plex token to use server management."
        case .invalidURL:
            return "Could not build a request for the Plex server."
        case .httpStatus(let code, _):
            switch code {
            case 401:
                return "Not authorized. Sign in with an account that can manage this server."
            case 403:
                return "This account does not have permission for that action."
            case 404:
                return "The Plex server could not find that item or session."
            case 503:
                return "The Plex server is busy. Try again in a moment."
            default:
                return "Plex server returned HTTP \(code)."
            }
        case .decodingFailed(let message):
            return message
        }
    }

    static func from(_ error: Error) -> String {
        if let plex = error as? PlexAPIError { return plex.adminUserMessage }
        return error.localizedDescription
    }
}
