//
//  PlexLiveTVClient.swift
//  EclipsePlexClient
//
//  Time-boxed Live TV / DVR API spike — list tuners and channels; stream URL resolution TBD.
//

import Foundation

nonisolated struct PlexLiveTVChannel: Identifiable, Hashable, Sendable {
    let ratingKey: String
    let title: String
    let thumbPath: String?

    var id: String { ratingKey }
}

nonisolated struct PlexLiveTVTuner: Identifiable, Hashable, Sendable {
    let key: String
    let title: String

    var id: String { key }
}

extension PlexMediaServerClient {
    /// Lists DVR / Live TV devices when the server exposes them.
    func fetchLiveTVTuners() async throws -> [PlexLiveTVTuner] {
        let rows = try await fetchAllRecords(path: "/livetv/tuners")
        return rows.compactMap { row in
            guard let key = row.key ?? row.ratingKey else { return nil }
            return PlexLiveTVTuner(key: key, title: row.displayTitle)
        }
    }

    /// Channel lineup for a tuner key from `/livetv/tuners/{key}/channels`.
    func fetchLiveTVChannels(tunerKey: String) async throws -> [PlexLiveTVChannel] {
        let path = "/livetv/tuners/\(tunerKey)/channels"
        let rows = try await fetchAllRecords(path: path)
        return rows.compactMap { row in
            guard let key = row.ratingKey else { return nil }
            return PlexLiveTVChannel(
                ratingKey: key,
                title: row.displayTitle,
                thumbPath: row.thumb
            )
        }
    }

    /// Whether this server reports any Live TV capability (best-effort).
    func hasLiveTV() async -> Bool {
        guard (try? await fetchLiveTVTuners()) != nil else { return false }
        return true
    }
}
