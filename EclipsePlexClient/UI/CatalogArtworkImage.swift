//
//  CatalogArtworkImage.swift
//  EclipsePlexClient
//
//  Loads poster-style artwork from `PlexServer.catalogArtworkURL(relativeThumbPath:)`.
//

import SwiftUI

struct CatalogArtworkImage: View {
    enum Style {
        case list
        case detailHero
        case hubTile

        fileprivate var size: CGSize {
            switch self {
            case .list: CGSize(width: 48, height: 72)
            case .detailHero: CGSize(width: 220, height: 330)
            case .hubTile: CGSize(width: 120, height: 180)
            }
        }

        fileprivate var cornerRadius: CGFloat {
            switch self {
            case .list: 6
            case .detailHero, .hubTile: 12
            }
        }
    }

    let plexServer: PlexServer
    let thumbPath: String?
    /// When set (e.g. offline Downloads catalog), artwork is loaded from this Plex server’s URL/token.
    var artworkServer: PlexServer? = nil
    var style: Style = .list
    /// 0...1 watch progress; drawn as a bar at the bottom of the artwork.
    var watchProgressFraction: Double? = nil
    /// Small badge when the item is saved for offline playback.
    var showsDownloadedBadge: Bool = false

    private var url: URL? {
        (artworkServer ?? plexServer).catalogArtworkURL(relativeThumbPath: thumbPath)
    }

    var body: some View {
        let s = style.size
        Group {
            if let url {
                CachedCatalogArtwork(
                    url: url,
                    size: s,
                    cornerRadius: style.cornerRadius
                )
            } else {
                placeholderContent
            }
        }
        .frame(width: s.width, height: s.height)
        .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        .overlay(alignment: .bottom) {
            if let fraction = watchProgressFraction, fraction > 0, fraction < 1 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(.white.opacity(0.9))
                        .frame(width: geo.size.width * fraction, height: 3)
                }
                .frame(height: 3)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsDownloadedBadge {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .green)
                    .padding(4)
                    .shadow(radius: 2)
            }
        }
    }

    private var placeholderContent: some View {
        ZStack {
            placeholderBackground
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.tertiary)
        }
    }

    private var placeholderBackground: some View {
        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            .fill(.quaternary.opacity(0.35))
    }
}

#Preview("List size") {
    let server = PlexSampleData.servers[0]
    CatalogArtworkImage(
        plexServer: server,
        thumbPath: "/library/metadata/100/thumb/200",
        style: .list
    )
    .padding()
}
