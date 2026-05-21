//
//  DownloadRecordArtwork.swift
//  EclipsePlexClient
//

import SwiftUI

/// Poster for an offline download row (loads from origin Plex server when online).
struct DownloadRecordArtwork: View {
    @EnvironmentObject private var downloadManager: OfflineDownloadManager
    let record: OfflineDownloadRecord
    var style: CatalogArtworkImage.Style = .list

    var body: some View {
        CatalogArtworkImage(
            plexServer: PlexServer.downloads,
            thumbPath: record.thumbPath,
            artworkServer: downloadManager.server(for: record),
            style: style
        )
    }
}
