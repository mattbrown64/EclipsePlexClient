//
//  PlexMediaServerClient+Playlists.swift
//  EclipsePlexClient
//

import Foundation

extension PlexMediaServerClient {
    func createPlaylist(title: String, librarySectionID: Int, type: String = "video") async throws -> String {
        var query = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "smart", value: "0"),
            URLQueryItem(name: "sectionID", value: String(librarySectionID)),
        ]
        let body = try await fetchOnePage(path: "/playlists", query: query, method: "POST")
        guard let key = body.records.first?.ratingKey ?? body.records.first?.key else {
            throw PlexAPIError.decodingFailed("Playlist create did not return a key.")
        }
        return key
    }

    func deletePlaylist(playlistKey: String) async throws {
        _ = try await fetchOnePage(path: "/playlists/\(playlistKey)", query: [], method: "DELETE")
    }

    func renamePlaylist(playlistKey: String, title: String) async throws {
        let query = [URLQueryItem(name: "title", value: title)]
        _ = try await fetchOnePage(path: "/playlists/\(playlistKey)", query: query, method: "PUT")
    }

    func addToPlaylist(playlistKey: String, metadataKey: String) async throws {
        let uri = metadataKey.hasPrefix("/library/metadata/")
            ? metadataKey
            : "/library/metadata/\(metadataKey)"
        let query = [URLQueryItem(name: "uri", value: "server://\(uri)")]
        _ = try await fetchOnePage(path: "/playlists/\(playlistKey)/items", query: query, method: "POST")
    }
}
