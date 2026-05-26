//
//  PlexMediaServerClient+ServerAdmin.swift
//  EclipsePlexClient
//

import Foundation

extension PlexMediaServerClient {

    // MARK: - Sessions

    func fetchActiveSessions() async throws -> [PlexActiveSession] {
        let xml = try await fetchXMLString(path: "/status/sessions", query: [])
        return PlexSessionsXMLParser.parse(xml)
    }

    func terminateSession(sessionId: String, reason: String = "Stopped by server admin") async throws {
        let query = [
            URLQueryItem(name: "sessionId", value: sessionId),
            URLQueryItem(name: "reason", value: reason),
        ]
        try await performAdminRequest(path: "/status/sessions/terminate", query: query, method: "POST")
    }

    // MARK: - Server status & prefs

    func fetchServerStatus() async throws -> PlexServerStatusInfo {
        let identity = try await fetchFriendlyName()
        let identityXML = try await fetchXMLString(path: "/identity", query: [])
        let version = PlexPrefsXMLParser.identityVersion(in: identityXML)
        let prefsXML = try await fetchXMLString(path: "/:/prefs", query: [])
        let prefs = PlexPrefsXMLParser.parseSettings(prefsXML)
        return PlexPrefsXMLParser.serverStatus(from: prefs, identityName: identity, identityVersion: version)
    }

    func fetchServerPrefs() async throws -> [String: String] {
        let xml = try await fetchXMLString(path: "/:/prefs", query: [])
        return PlexPrefsXMLParser.parseSettings(xml)
    }

    func updateServerPref(id: String, value: String) async throws {
        let query = [URLQueryItem(name: id, value: value)]
        try await performAdminRequest(path: "/:/prefs", query: query, method: "PUT")
    }

    // MARK: - Users

    func fetchServerUsers() async throws -> [PlexServerUser] {
        let xml = try await fetchXMLString(path: "/accounts", query: [])
        return PlexAccountsXMLParser.parse(xml)
    }

    // MARK: - Library maintenance

    func refreshLibrarySection(sectionID: String, scanFiles: Bool) async throws {
        let query = [URLQueryItem(name: "force", value: scanFiles ? "1" : "0")]
        _ = try await fetchXMLString(path: "/library/sections/\(sectionID)/refresh", query: query)
    }

    func analyzeLibrarySection(sectionID: String) async throws {
        try await performAdminRequest(
            path: "/library/sections/\(sectionID)/analyze",
            query: [],
            method: "PUT"
        )
    }

    func emptyLibraryTrash(sectionID: String) async throws {
        try await performAdminRequest(
            path: "/library/sections/\(sectionID)/emptyTrash",
            query: [],
            method: "PUT"
        )
    }

    func updateLibrarySectionTitle(sectionID: String, title: String) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let query = [
            URLQueryItem(name: "title.value", value: trimmed),
            URLQueryItem(name: "title.locked", value: "1"),
        ]
        try await performAdminRequest(
            path: "/library/sections/\(sectionID)",
            query: query,
            method: "PUT"
        )
    }

    func deleteLibrarySection(sectionID: String) async throws {
        let query = [URLQueryItem(name: "async", value: "1")]
        try await performAdminRequest(
            path: "/library/sections/\(sectionID)",
            query: query,
            method: "DELETE"
        )
    }

    // MARK: - Metadata matches & edits

    func fetchMetadataMatchCandidates(
        ratingKey: String,
        hints: FixMatchSearchHints
    ) async throws -> [PlexMetadataMatchCandidate] {
        var query = [URLQueryItem(name: "manual", value: hints.manual ? "1" : "0")]
        if let title = hints.trimmedTitle {
            query.append(URLQueryItem(name: "title", value: title))
        }
        if let year = hints.year {
            query.append(URLQueryItem(name: "year", value: String(year)))
        }
        if let showTitle = hints.trimmedShowTitle {
            query.append(URLQueryItem(name: "grandparentTitle", value: showTitle))
        }
        if let seasonTitle = hints.trimmedSeasonTitle {
            query.append(URLQueryItem(name: "parentTitle", value: seasonTitle))
        }
        let id = Self.normalizedMetadataID(ratingKey)
        let xml = try await fetchXMLString(path: "/library/metadata/\(id)/matches", query: query)
        return PlexMetadataMatchXMLParser.parse(xml)
    }

    func fetchMetadataMatchCandidates(
        ratingKey: String,
        title: String?,
        year: Int?,
        manual: Bool = true
    ) async throws -> [PlexMetadataMatchCandidate] {
        try await fetchMetadataMatchCandidates(
            ratingKey: ratingKey,
            hints: FixMatchSearchHints(title: title, year: year, manual: manual)
        )
    }

    func applyMetadataMatch(ratingKey: String, guid: String) async throws {
        let id = Self.normalizedMetadataID(ratingKey)
        var request = try makeRequest(
            path: "/library/metadata/\(id)/match",
            query: [URLQueryItem(name: "guid", value: guid)]
        )
        request.httpMethod = "PUT"
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        try await executeAdminRequest(request)
    }

    func refreshItemMetadata(ratingKey: String) async throws {
        let id = Self.normalizedMetadataID(ratingKey)
        var request = try makeRequest(
            path: "/library/metadata/\(id)",
            query: [URLQueryItem(name: "refresh", value: "1")]
        )
        request.httpMethod = "PUT"
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        try await executeAdminRequest(request)
    }

    func updateItemMetadata(ratingKey: String, edit: PlexMetadataEditRequest) async throws {
        let id = Self.normalizedMetadataID(ratingKey)
        var query: [URLQueryItem] = []
        if let title = edit.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            query.append(URLQueryItem(name: "title.value", value: title))
            if edit.lockTitle { query.append(URLQueryItem(name: "title.locked", value: "1")) }
        }
        if let summary = edit.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            query.append(URLQueryItem(name: "summary.value", value: summary))
            if edit.lockSummary { query.append(URLQueryItem(name: "summary.locked", value: "1")) }
        }
        if let year = edit.year {
            query.append(URLQueryItem(name: "year.value", value: String(year)))
            if edit.lockYear { query.append(URLQueryItem(name: "year.locked", value: "1")) }
        }
        guard !query.isEmpty else { return }
        var request = try makeRequest(path: "/library/metadata/\(id)", query: query)
        request.httpMethod = "PUT"
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        try await executeAdminRequest(request)
    }

    func deleteItemMetadata(ratingKey: String) async throws {
        let id = Self.normalizedMetadataID(ratingKey)
        var request = try makeRequest(path: "/library/metadata/\(id)", query: [])
        request.httpMethod = "DELETE"
        try await executeAdminRequest(request)
    }

    func optimizeItemMetadata(ratingKey: String) async throws {
        let id = Self.normalizedMetadataID(ratingKey)
        try await performAdminRequest(
            path: "/library/metadata/\(id)/optimize",
            query: [],
            method: "PUT"
        )
    }

    // MARK: - HTTP helpers

    func fetchXMLString(path: String, query: [URLQueryItem]) async throws -> String {
        var request = try makeRequest(path: path, query: query)
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PlexAPIError.decodingFailed("Invalid response.")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8).map { String($0.prefix(280)) }
            throw PlexAPIError.httpStatus(code: http.statusCode, bodySnippet: snippet)
        }
        guard let xml = String(data: data, encoding: .utf8) else {
            throw PlexAPIError.decodingFailed("Could not read Plex XML.")
        }
        return xml
    }

    private func performAdminRequest(path: String, query: [URLQueryItem], method: String) async throws {
        var request = try makeRequest(path: path, query: query)
        request.httpMethod = method
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        try await executeAdminRequest(request)
    }

    private func executeAdminRequest(_ request: URLRequest) async throws {
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode) else {
            throw PlexAPIError.httpStatus(code: (response as? HTTPURLResponse)?.statusCode ?? -1, bodySnippet: nil)
        }
    }

    private static func normalizedMetadataID(_ ratingKey: String) -> String {
        let trimmed = ratingKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/library/metadata/") {
            return String(trimmed.dropFirst("/library/metadata/".count))
        }
        return trimmed
    }
}
