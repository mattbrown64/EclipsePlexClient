//
//  PlexAccountAPI.swift
//  EclipsePlexClient
//
//  Plex.tv: PIN auth + /api/v2/resources for discovering Media Servers on the user's account.
//

import CryptoKit
import Foundation

nonisolated enum PlexAccountError: LocalizedError, Sendable {
    case invalidResponse
    case pinAuthTimeout

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Unexpected response from Plex."
        case .pinAuthTimeout: return "Sign-in timed out. Try again."
        }
    }
}

nonisolated enum PlexAccountAPI: Sendable {

    // MARK: - PIN

    struct PinStart: Sendable {
        let id: Int
        let code: String
    }

    /// Opens this URL (e.g. in a browser) so the user can approve the app.
    static func plexAuthPageURL(clientIdentifier: String, pinCode: String) -> URL? {
        let encID = clientIdentifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientIdentifier
        let encCode = pinCode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pinCode
        return URL(string: "https://app.plex.tv/auth#!?clientID=\(encID)&code=\(encCode)")
    }

    /// Creates a sign-in PIN (`strong` tokens for third-party apps).
    static func createPin(session: URLSession = .shared) async throws -> PinStart {
        let cid = PlexHTTPConstants.clientIdentifier
        guard let url = URL(string: "https://plex.tv/api/v2/pins.json?strong=true") else {
            throw PlexAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(PlexHTTPConstants.productName, forHTTPHeaderField: "X-Plex-Product")
        req.setValue(PlexHTTPConstants.productVersion, forHTTPHeaderField: "X-Plex-Version")
        req.setValue(cid, forHTTPHeaderField: "X-Plex-Client-Identifier")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw PlexAccountError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(PlexPinDTO.self, from: data)
        return PinStart(id: decoded.id, code: decoded.code)
    }

    /// `authToken` when the user has finished signing in; `nil` if still pending.
    static func pinStatus(pinId: Int, session: URLSession = .shared) async throws -> String? {
        let cid = PlexHTTPConstants.clientIdentifier
        guard let url = URL(string: "https://plex.tv/api/v2/pins/\(pinId)") else {
            throw PlexAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(cid, forHTTPHeaderField: "X-Plex-Client-Identifier")
        req.setValue(PlexHTTPConstants.productName, forHTTPHeaderField: "X-Plex-Product")
        req.setValue(PlexHTTPConstants.productVersion, forHTTPHeaderField: "X-Plex-Version")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw PlexAccountError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(PlexPinDTO.self, from: data)
        let token = decoded.authToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (token?.isEmpty == false) ? token : nil
    }

    /// Poll until `authToken` appears or `timeoutSeconds` elapses.
    static func pollForAccountToken(pinId: Int, pollIntervalNanoseconds: UInt64 = 1_000_000_000, timeoutSeconds: Int = 240, session: URLSession = .shared) async throws -> String {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            try Task.checkCancellation()
            if let token = try await pinStatus(pinId: pinId, session: session) {
                return token
            }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        throw PlexAccountError.pinAuthTimeout
    }

    // MARK: - Resources → PlexServer

    /// Media Servers visible to this Plex account (owned and shared).
    static func fetchMediaServers(accountToken: String, session: URLSession = .shared) async throws -> [PlexServer] {
        let cid = PlexHTTPConstants.clientIdentifier
        guard var components = URLComponents(string: "https://plex.tv/api/v2/resources") else {
            throw PlexAPIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "includeHttps", value: "1"),
            URLQueryItem(name: "includeRelay", value: "1"),
            URLQueryItem(name: "includeIPv6", value: "1"),
        ]
        guard let url = components.url else { throw PlexAPIError.invalidURL }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(accountToken, forHTTPHeaderField: "X-Plex-Token")
        req.setValue(cid, forHTTPHeaderField: "X-Plex-Client-Identifier")
        req.setValue(PlexHTTPConstants.productName, forHTTPHeaderField: "X-Plex-Product")
        req.setValue(PlexHTTPConstants.productVersion, forHTTPHeaderField: "X-Plex-Version")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw PlexAccountError.invalidResponse
        }

        let devices = try decodeResourceList(from: data)
        var servers: [PlexServer] = []
        for d in devices {
            if let s = await mapResourceToReachableServer(d, session: session) {
                servers.append(s)
            }
        }
        return servers
    }

    private static func decodeResourceList(from data: Data) throws -> [PlexResourceDeviceDTO] {
        let decoders: [JSONDecoder] = {
            let plain = JSONDecoder()
            let snake = JSONDecoder()
            snake.keyDecodingStrategy = .convertFromSnakeCase
            return [plain, snake]
        }()
        for decoder in decoders {
            if let arr = try? decoder.decode([PlexResourceDeviceDTO].self, from: data) {
                return arr
            }
            struct Wrap: Decodable { let data: [PlexResourceDeviceDTO]? }
            if let w = try? decoder.decode(Wrap.self, from: data), let d = w.data {
                return d
            }
            struct MC: Decodable { let MediaContainer: [PlexResourceDeviceDTO]? }
            if let mc = try? decoder.decode(MC.self, from: data), let d = mc.MediaContainer {
                return d
            }
        }
        throw PlexAPIError.decodingFailed("Could not parse Plex resources JSON.")
    }

    /// Builds a `PlexServer` by trying each connection (best first) until PMS responds to `/identity`.
    /// Avoids picking a single "best" URL that fails DNS (common with `*.plex.direct` when not on the right network).
    private static func mapResourceToReachableServer(_ d: PlexResourceDeviceDTO, session: URLSession) async -> PlexServer? {
        let provides = (d.provides ?? "").lowercased()
        guard provides.contains("server") else { return nil }

        let access = d.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !access.isEmpty else { return nil }

        let rid = d.clientIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rid.isEmpty else { return nil }

        let candidates = buildProbeCandidates(connections: d.connections ?? [], httpsRequired: d.httpsRequiredBool)
        let sorted = candidates.sorted { $0.score > $1.score }
        guard !sorted.isEmpty else { return nil }

        let name = d.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Plex Server"
        let id = UUID.stableFromPlexResourceIdentifier(rid)

        for entry in sorted {
            let server = PlexServer(
                id: id,
                name: name,
                hostDescription: entry.url,
                accessToken: access,
                plexResourceClientIdentifier: rid
            )
            guard server.usesLivePlexAPI else { continue }
            do {
                let client = try PlexMediaServerClient(server: server, session: session)
                try await client.verifyReachable()
                return server
            } catch {
                continue
            }
        }
        return nil
    }

    /// Plex lists a `uri` plus often `address`/`port`. We synthesize `http(s)://address:port` so we can reach
    /// the server on home LAN even when `*.plex.direct` points at Tailscale/CGNAT (`100.64.0.0/10`) that is not
    /// routable from the current network (-1004).
    private static func buildProbeCandidates(
        connections: [PlexResourceConnectionDTO],
        httpsRequired: Bool
    ) -> [(url: String, score: Int)] {
        var seen = Set<String>()
        var out: [(String, Int)] = []

        func append(_ raw: String, conn: PlexResourceConnectionDTO) {
            guard let normalized = normalizedBaseURLString(raw) else { return }
            guard seen.insert(normalized).inserted else { return }
            let score = scoreProbeURL(normalized, conn: conn, httpsRequired: httpsRequired)
            out.append((normalized, score))
        }

        for c in connections {
            let uri = c.uri.trimmingCharacters(in: .whitespacesAndNewlines)
            if !uri.isEmpty {
                append(uri, conn: c)
                if let u = URL(string: uri),
                   let host = u.host?.lowercased(),
                   let embedded = embeddedIPv4FromPlexDirect(host) {
                    let port = u.port ?? 32400
                    append("http://\(embedded):\(port)", conn: c)
                    append("https://\(embedded):\(port)", conn: c)
                }
            }

            guard let addr = c.address?.trimmingCharacters(in: .whitespacesAndNewlines), !addr.isEmpty,
                  let port = c.port else { continue }

            append("http://\(addr):\(port)", conn: c)
            append("https://\(addr):\(port)", conn: c)
        }
        return out
    }

    private static func normalizedBaseURLString(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        guard var parts = URLComponents(string: t) else { return t }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        parts.fragment = nil
        parts.query = nil
        if parts.path == "/" { parts.path = "" }
        return parts.string ?? t
    }

    private static func scoreProbeURL(
        _ urlString: String,
        conn: PlexResourceConnectionDTO,
        httpsRequired: Bool
    ) -> Int {
        var s = 0
        if conn.localBool { s += 260 }
        if conn.relayBool { s -= 130 }

        guard let u = URL(string: urlString), let hostRaw = u.host else { return s - 500 }
        let host = hostRaw.lowercased()

        let ipForClass = embeddedIPv4FromPlexDirect(host) ?? (isIPv4Literal(host) ? host : nil)
        if let ip = ipForClass {
            switch rfc1918Kind(ip) {
            case .rfc1918Private: s += 520
            case .cgnatTailscale: s += 130
            case .otherPublic: s += 220
            }
        } else {
            s += 80
        }

        if host.contains(".plex.direct") { s -= 95 }

        let scheme = u.scheme?.lowercased() ?? ""
        if scheme == "http" {
            s += 55
            if httpsRequired { s -= 75 }
        } else if scheme == "https" {
            s += 42
        }

        return s
    }

    /// `100-76-182-190.<token>.plex.direct` → `100.76.182.190`
    private static func embeddedIPv4FromPlexDirect(_ host: String) -> String? {
        guard host.contains(".plex.direct") else { return nil }
        guard let firstLabel = host.split(separator: ".").first else { return nil }
        let octets = firstLabel.split(separator: "-")
        guard octets.count == 4, octets.allSatisfy({ Int($0) != nil }) else { return nil }
        return octets.map(String.init).joined(separator: ".")
    }

    private enum IPv4LANClass: Sendable {
        case rfc1918Private
        case cgnatTailscale
        case otherPublic
    }

    private static func rfc1918Kind(_ ipv4: String) -> IPv4LANClass {
        let parts = ipv4.split(separator: ".")
        guard parts.count == 4, let a = Int(parts[0]), let b = Int(parts[1]) else { return .otherPublic }
        if a == 10 { return .rfc1918Private }
        if a == 172, (16 ... 31).contains(b) { return .rfc1918Private }
        if a == 192, b == 168 { return .rfc1918Private }
        if a == 100, (64 ... 127).contains(b) { return .cgnatTailscale }
        return .otherPublic
    }

    private static func isIPv4Literal(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        for p in parts {
            guard let n = Int(p), (0 ... 255).contains(n) else { return false }
        }
        return true
    }
}

// MARK: - DTOs

private nonisolated struct PlexPinDTO: Decodable {
    let id: Int
    let code: String
    let authToken: String?

    enum CodingKeys: String, CodingKey { case id, code, authToken }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .id) {
            id = i
        } else if let s = try? c.decode(String.self, forKey: .id), let i = Int(s) {
            id = i
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Expected pin id")
        }
        code = try c.decode(String.self, forKey: .code)
        authToken = try c.decodeIfPresent(String.self, forKey: .authToken)
    }
}

private nonisolated struct PlexResourceDeviceDTO: Decodable {
    let name: String?
    let provides: String?
    let clientIdentifier: String?
    let accessToken: String?
    let httpsRequired: PlexFlexibleBoolInt?
    let connections: [PlexResourceConnectionDTO]?

    var httpsRequiredBool: Bool { httpsRequired?.truth ?? false }
}

private nonisolated struct PlexResourceConnectionDTO: Decodable {
    let uri: String
    let proto: String?
    let local: PlexFlexibleBoolInt?
    let relay: PlexFlexibleBoolInt?
    let address: String?
    let port: Int?

    enum CodingKeys: String, CodingKey {
        case uri
        case proto = "protocol"
        case local, relay, address, port
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uri = (try c.decodeIfPresent(String.self, forKey: .uri)) ?? ""
        proto = try c.decodeIfPresent(String.self, forKey: .proto)
        local = try c.decodeIfPresent(PlexFlexibleBoolInt.self, forKey: .local)
        relay = try c.decodeIfPresent(PlexFlexibleBoolInt.self, forKey: .relay)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        if let p = try c.decodeIfPresent(Int.self, forKey: .port) {
            port = p
        } else if let s = try c.decodeIfPresent(String.self, forKey: .port), let p = Int(s) {
            port = p
        } else {
            port = nil
        }
    }

    var localBool: Bool { local?.truth ?? false }
    var relayBool: Bool { relay?.truth ?? false }
}

/// Plex JSON sometimes uses `true`/`false`, `0`/`1`, or string `"0"`.
private nonisolated struct PlexFlexibleBoolInt: Decodable {
    let truth: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) {
            truth = b
            return
        }
        if let i = try? c.decode(Int.self) {
            truth = i != 0
            return
        }
        if let s = try? c.decode(String.self) {
            truth = (s as NSString).boolValue || s == "1"
            return
        }
        truth = false
    }
}

private nonisolated extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

nonisolated extension UUID {
    /// Stable id for a Plex `clientIdentifier` so the same server maps to one row across launches.
    static func stableFromPlexResourceIdentifier(_ string: String) -> UUID {
        let digest = SHA256.hash(data: Data(string.utf8))
        var b = Array(digest.prefix(16))
        b[6] = (b[6] & 0x0F) | 0x40
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(
            uuid: (
                b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]
            )
        )
    }
}
