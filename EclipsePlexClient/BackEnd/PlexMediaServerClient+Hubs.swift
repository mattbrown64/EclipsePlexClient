//
//  PlexMediaServerClient+Hubs.swift
//  EclipsePlexClient
//

import Foundation

extension PlexMediaServerClient {

    /// Hubs for a library section (Recommended tab).
    func fetchSectionHubs(library: PlexLibrary, count: Int = 15) async throws -> [PlexHubShelf] {
        let section = library.sectionID
        let query = [URLQueryItem(name: "count", value: String(max(1, count)))]
        let dtos = try await fetchHubDTOs(path: "/hubs/sections/\(section)", query: query)
        return mapHubShelves(dtos, library: library)
    }

    /// Related hub shelves for a metadata item (detail page).
    func fetchRelatedHubShelves(
        ratingKey: String,
        library: PlexLibrary,
        count: Int = 12
    ) async throws -> [PlexHubShelf] {
        let query = [URLQueryItem(name: "count", value: String(max(1, count)))]
        let dtos = try await fetchHubDTOs(path: "/hubs/metadata/\(ratingKey)/related", query: query)
        return mapHubShelves(dtos, library: library)
    }

    private func fetchHubDTOs(path: String, query: [URLQueryItem]) async throws -> [PlexHubDTO] {
        var request = try makeRequest(path: path, query: query)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PlexAPIError.decodingFailed("Invalid hub response.")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8).map { String($0.prefix(280)) }
            throw PlexAPIError.httpStatus(code: http.statusCode, bodySnippet: snippet)
        }
        do {
            let root = try JSONDecoder().decode(PlexHubsRoot.self, from: data)
            return root.MediaContainer.hubDTOs
        } catch {
            throw PlexAPIError.decodingFailed("Could not read Plex hubs (\(error.localizedDescription)).")
        }
    }

    private func mapHubShelves(_ dtos: [PlexHubDTO], library: PlexLibrary) -> [PlexHubShelf] {
        dtos.compactMap { dto in
            let title = (dto.title ?? "Recommended").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let hits: [PlexCatalogSearchHit] = dto.records.enumerated().compactMap { index, record in
                guard let node = catalogNodeForRecord(record, libraryOrder: index) else { return nil }
                return PlexCatalogSearchHit(library: library, node: node)
            }
            guard !hits.isEmpty else { return nil }
            return PlexHubShelf(id: dto.stableID, title: title, hits: hits)
        }
    }
}
