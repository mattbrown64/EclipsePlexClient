//
//  PlexServer+ConnectionStatus.swift
//  EclipsePlexClient
//

import Foundation

/// Why a Plex server cannot load libraries or hubs.
nonisolated enum PlexServerConnectionIssue: Equatable {
    case missingToken
    case invalidAddress
    case offline
    case librariesFailed(String)

    var title: String {
        switch self {
        case .missingToken:
            return "Token missing"
        case .invalidAddress:
            return "Invalid address"
        case .offline:
            return "Server unreachable"
        case .librariesFailed:
            return "Libraries unavailable"
        }
    }

    var message: String {
        switch self {
        case .missingToken:
            return "This server has no Plex access token. Edit the server to sign in again or paste a token."
        case .invalidAddress:
            return "The server address could not be parsed. Edit the server URL (e.g. https://host:32400)."
        case .offline:
            return "Could not reach the Plex server at the saved address. Check the network or try another connection."
        case .librariesFailed(let detail):
            return detail
        }
    }

    var systemImage: String {
        switch self {
        case .missingToken:
            return "key.slash"
        case .invalidAddress:
            return "network.slash"
        case .offline:
            return "wifi.exclamationmark"
        case .librariesFailed:
            return "books.vertical"
        }
    }

    var needsEditServer: Bool {
        switch self {
        case .missingToken, .invalidAddress:
            return true
        case .offline, .librariesFailed:
            return false
        }
    }

    var canRetryLibraries: Bool {
        switch self {
        case .missingToken, .invalidAddress:
            return false
        case .offline, .librariesFailed:
            return true
        }
    }

    /// PIN sign-in can restore tokens for account-discovered servers.
    var offersPlexAccountSignIn: Bool {
        if case .missingToken = self { return true }
        return false
    }

    /// Short label for the server row in the sidebar.
    var serverRowSubtitle: String {
        switch self {
        case .missingToken:
            return "Token missing"
        case .invalidAddress:
            return "Invalid address"
        case .offline:
            return "Unreachable"
        case .librariesFailed:
            return "Libraries failed to load"
        }
    }
}

extension PlexServer {
    /// Highest-priority connection problem for this server, if any.
    static func connectionIssue(
        for server: PlexServer,
        reachable: Bool?,
        librariesLoadError: String?,
        librariesLoadErrorServerID: UUID?
    ) -> PlexServerConnectionIssue? {
        guard !server.isDownloadsServer else { return nil }

        let prepared = server.withTokenFromKeychain().withActiveConnection()
        let token = KeychainStore.token(forServerID: server.id)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if token.isEmpty {
            return .missingToken
        }
        if prepared.plexOriginURL == nil {
            return .invalidAddress
        }
        if reachable == false {
            return .offline
        }
        if librariesLoadErrorServerID == server.id,
           let librariesLoadError,
           !librariesLoadError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .librariesFailed(librariesLoadError)
        }
        return nil
    }

    /// User-facing message stored in `librariesLoadError` when live API is not available.
    static func configurationLibrariesError(for server: PlexServer) -> String {
        connectionIssue(
            for: server,
            reachable: nil,
            librariesLoadError: nil,
            librariesLoadErrorServerID: nil
        )?.message ?? "This server needs a reachable URL and Plex token."
    }
}
