//
//  OfflineDownloadCatalog.swift
//  EclipsePlexClient
//

import Foundation

/// Builds `PlexCatalogNode` trees for the virtual Downloads server (movies + TV grouped by show).
enum OfflineDownloadCatalog {
    static let recordRatingKeyPrefix = "offline-record:"
    static let showRatingKeyPrefix = "offline-show:"

    static func nodes(
        records: [OfflineDownloadRecord],
        library: PlexLibrary,
        parent: PlexCatalogParent
    ) -> [PlexCatalogNode] {
        let playable = records.filter(\.isPlayable)
        if OfflineDownloadsLibrary.isMovies(library) {
            return movieNodes(from: playable, parent: parent)
        }
        if OfflineDownloadsLibrary.isTV(library) {
            return tvNodes(from: playable, parent: parent)
        }
        return []
    }

    static func recordID(fromCatalogRatingKey ratingKey: String) -> UUID? {
        guard ratingKey.hasPrefix(recordRatingKeyPrefix) else { return nil }
        return UUID(uuidString: String(ratingKey.dropFirst(recordRatingKeyPrefix.count)))
    }

    static func showGroupKey(fromCatalogRatingKey ratingKey: String) -> String? {
        guard ratingKey.hasPrefix(showRatingKeyPrefix) else { return nil }
        return String(ratingKey.dropFirst(showRatingKeyPrefix.count))
    }

    static func catalogRatingKey(for recordID: UUID) -> String {
        "\(recordRatingKeyPrefix)\(recordID.uuidString)"
    }

    static func showCatalogRatingKey(groupKey: String) -> String {
        "\(showRatingKeyPrefix)\(groupKey)"
    }

    // MARK: - Movies

    private static func movieNodes(
        from records: [OfflineDownloadRecord],
        parent: PlexCatalogParent
    ) -> [PlexCatalogNode] {
        guard case .root = parent else { return [] }
        return records
            .filter { $0.resolvedMediaKind == .movie }
            .sorted { $0.createdAt > $1.createdAt }
            .enumerated()
            .map { index, record in
                .movie(
                    PlexMovieSummary(
                        ratingKey: catalogRatingKey(for: record.id),
                        title: record.displayTitle,
                        year: nil,
                        summary: nil,
                        thumbPath: record.thumbPath,
                        libraryOrder: index,
                        addedAt: Int(record.completedAt?.timeIntervalSince1970 ?? record.createdAt.timeIntervalSince1970)
                    )
                )
            }
    }

    // MARK: - TV (shows → episodes)

    private static func tvNodes(
        from records: [OfflineDownloadRecord],
        parent: PlexCatalogParent
    ) -> [PlexCatalogNode] {
        let episodes = records.filter { $0.resolvedMediaKind == .episode }
        switch parent {
        case .root:
            return showNodes(from: episodes)
        case .show(let showKey):
            guard let groupKey = showGroupKey(fromCatalogRatingKey: showKey) else { return [] }
            return episodeNodes(from: episodes, groupKey: groupKey)
        case .season, .collection, .playlist:
            return []
        }
    }

    private static func showNodes(from episodes: [OfflineDownloadRecord]) -> [PlexCatalogNode] {
        let grouped = Dictionary(grouping: episodes, by: \.showGroupKey)
        return grouped.keys.sorted().enumerated().compactMap { index, groupKey -> PlexCatalogNode? in
            guard let items = grouped[groupKey], let first = items.first else { return nil }
            let title = first.resolvedShowTitle
            let thumb = items.compactMap(\.showThumbPath).first
                ?? items.compactMap(\.thumbPath).first
            let episodeCount = items.count
            let origins = Set(items.map(\.serverName)).sorted().joined(separator: ", ")
            return .show(
                PlexShowSummary(
                    ratingKey: showCatalogRatingKey(groupKey: groupKey),
                    title: title,
                    year: nil,
                    summary: "\(episodeCount) episode\(episodeCount == 1 ? "" : "s") · From \(origins)",
                    thumbPath: thumb,
                    libraryOrder: index
                )
            )
        }
    }

    private static func episodeNodes(
        from episodes: [OfflineDownloadRecord],
        groupKey: String
    ) -> [PlexCatalogNode] {
        episodes
            .filter { $0.showGroupKey == groupKey }
            .sorted { lhs, rhs in
                let ls = lhs.resolvedSeasonNumber ?? 0
                let rs = rhs.resolvedSeasonNumber ?? 0
                if ls != rs { return ls < rs }
                let le = lhs.resolvedEpisodeNumber ?? 0
                let re = rhs.resolvedEpisodeNumber ?? 0
                if le != re { return le < re }
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
            .enumerated()
            .map { index, record in
                .episode(
                    PlexEpisodeSummary(
                        ratingKey: catalogRatingKey(for: record.id),
                        parentRatingKey: showCatalogRatingKey(groupKey: groupKey),
                        showRatingKey: showCatalogRatingKey(groupKey: groupKey),
                        showTitle: record.resolvedShowTitle,
                        seasonNumber: record.resolvedSeasonNumber ?? 0,
                        episodeNumber: record.resolvedEpisodeNumber ?? 0,
                        title: record.episodeDisplayTitle,
                        summary: "From \(record.serverName)",
                        durationSeconds: nil,
                        thumbPath: record.thumbPath,
                        libraryOrder: index
                    )
                )
            }
    }
}
