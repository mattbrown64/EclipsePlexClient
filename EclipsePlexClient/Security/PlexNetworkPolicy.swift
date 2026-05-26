//
//  PlexNetworkPolicy.swift
//  EclipsePlexClient
//

import Foundation

/// LAN HTTP + WAN HTTPS only (policy A from production plan).
enum PlexNetworkPolicy {
    enum ValidationError: LocalizedError, Sendable {
        case invalidHost
        case insecureRemoteHTTP

        var errorDescription: String? {
            switch self {
            case .invalidHost:
                return "Enter a valid server address (host, host:port, or https://…)."
            case .insecureRemoteHTTP:
                return "HTTP is only allowed for local network servers. Use https:// for remote connections."
            }
        }
    }

    /// Validates a user-entered host/URL before saving.
    static func validateHostDescription(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.invalidHost }
        guard let url = normalizedURL(from: trimmed) else { throw ValidationError.invalidHost }
        if url.scheme?.lowercased() == "http", !isLocalNetworkHost(url) {
            throw ValidationError.insecureRemoteHTTP
        }
        return trimmed
    }

    /// Whether ATS should allow cleartext to this origin (local HTTP Plex servers).
    static func allowsInsecureHTTP(to url: URL) -> Bool {
        url.scheme?.lowercased() == "http" && isLocalNetworkHost(url)
    }

    static func normalizedURL(from hostDescription: String) -> URL? {
        let trimmed = hostDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.host != nil { return url }
        if trimmed.contains("://") { return URL(string: trimmed) }
        return URL(string: "https://\(trimmed)")
    }

    static func isLocalNetworkHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "localhost" || host.hasSuffix(".local") { return true }
        if host.hasSuffix(".plex.direct") { return true }
        return isPrivateIPv4(host) || isPrivateIPv6(host)
    }

    private static func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ Int($0) != nil }) else { return false }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch octets[0] {
        case 10: return true
        case 127: return true
        case 169: return octets[1] == 254
        case 172: return (16...31).contains(octets[1])
        case 192: return octets[1] == 168
        default: return false
        }
    }

    private static func isPrivateIPv6(_ host: String) -> Bool {
        let h = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
        if h == "::1" { return true }
        if h.lowercased().hasPrefix("fe80:") { return true }
        if h.lowercased().hasPrefix("fc") || h.lowercased().hasPrefix("fd") { return true }
        return false
    }
}
