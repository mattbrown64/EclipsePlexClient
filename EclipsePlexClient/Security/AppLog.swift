//
//  AppLog.swift
//  EclipsePlexClient
//

import Foundation
import os

/// Structured logging with redaction. Verbose logs only in DEBUG.
enum AppLog {
    private static let network = Logger(subsystem: subsystem, category: "network")
    private static let playback = Logger(subsystem: subsystem, category: "playback")
    private static let offline = Logger(subsystem: subsystem, category: "offline")
    private static let ui = Logger(subsystem: subsystem, category: "ui")

    private static var subsystem: String {
        Bundle.main.bundleIdentifier ?? "EclipsePlexClient"
    }

    static func network(_ message: String) {
        network.info("\(redact(message), privacy: .public)")
    }

    static func networkDebug(_ message: String) {
        #if DEBUG
        network.debug("\(redact(message), privacy: .public)")
        #endif
    }

    static func playback(_ message: String) {
        playback.info("\(redact(message), privacy: .public)")
    }

    static func playbackDebug(_ message: String) {
        #if DEBUG
        playback.debug("\(redact(message), privacy: .public)")
        #endif
    }

    static func offline(_ message: String) {
        offline.info("\(redact(message), privacy: .public)")
    }

    static func offlineDebug(_ message: String) {
        #if DEBUG
        offline.debug("\(redact(message), privacy: .public)")
        #endif
    }

    static func ui(_ message: String) {
        ui.info("\(redact(message), privacy: .public)")
    }

    /// Redacts tokens, common auth query params, and bearer-like values.
    static func redact(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.host != nil, let redacted = redactURL(url) {
            return redacted
        }
        var result = text
        result = redactParameter(prefix: "X-Plex-Token=", in: result)
        result = redactParameter(prefix: "authToken=", in: result)
        if let bearer = result.range(of: "Bearer ", options: .caseInsensitive) {
            let start = bearer.upperBound
            let end = result[start...].firstIndex(where: { $0.isWhitespace || $0 == "\"" }) ?? result.endIndex
            result.replaceSubrange(start..<end, with: "***")
        }
        return result
    }

    private static func redactParameter(prefix: String, in text: String) -> String {
        var result = text
        guard let range = result.range(of: prefix, options: .caseInsensitive) else { return result }
        let start = range.upperBound
        let end = result[start...].firstIndex(where: { $0.isWhitespace || $0 == "&" || $0 == "\"" }) ?? result.endIndex
        result.replaceSubrange(start..<end, with: "***")
        return result
    }

    static func redactURL(_ url: URL?) -> String? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url?.absoluteString
        }
        if let items = components.queryItems,
           items.contains(where: { $0.name == "X-Plex-Token" }) {
            components.queryItems = items.map { item in
                item.name == "X-Plex-Token" ? URLQueryItem(name: item.name, value: "***") : item
            }
        }
        return components.string ?? url.absoluteString
    }
}
