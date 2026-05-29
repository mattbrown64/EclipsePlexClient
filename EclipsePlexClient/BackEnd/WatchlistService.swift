//
//  WatchlistService.swift
//  EclipsePlexClient
//

import Foundation

struct WatchlistItem: Identifiable, Hashable, Sendable {
    let id: String
    let ratingKey: String
    let title: String
    let thumb: String?
    let year: Int?
}

/// Fetches Plex Discover watchlist using the Plex.tv account token.
enum WatchlistService {
    private static let endpoint = URL(string: "https://discover-provider.plex.tv/library/sections/watchlist/all")!

    static func fetchItems(accountToken: String) async throws -> [WatchlistItem] {
        var request = URLRequest(url: endpoint)
        request.setValue(accountToken, forHTTPHeaderField: "X-Plex-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw PlexAPIError.httpStatus(
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                bodySnippet: nil
            )
        }
        return try parseJSON(data)
    }

    private static func parseJSON(_ data: Data) throws -> [WatchlistItem] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let container = root["MediaContainer"] as? [String: Any]
        let metadata = container?["Metadata"] as? [[String: Any]] ?? []
        return metadata.compactMap { row -> WatchlistItem? in
            guard let ratingKey = row["ratingKey"] as? String ?? (row["ratingKey"] as? Int).map(String.init),
                  let title = row["title"] as? String
            else { return nil }
            let thumb = row["thumb"] as? String
            let year = row["year"] as? Int
            return WatchlistItem(
                id: ratingKey,
                ratingKey: ratingKey,
                title: title,
                thumb: thumb,
                year: year
            )
        }
    }
}
