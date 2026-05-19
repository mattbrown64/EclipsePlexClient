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

        fileprivate var size: CGSize {
            switch self {
            case .list: CGSize(width: 48, height: 72)
            case .detailHero: CGSize(width: 220, height: 330)
            }
        }

        fileprivate var cornerRadius: CGFloat {
            switch self {
            case .list: 6
            case .detailHero: 12
            }
        }
    }

    let plexServer: PlexServer
    let thumbPath: String?
    var style: Style = .list

    private var url: URL? {
        plexServer.catalogArtworkURL(relativeThumbPath: thumbPath)
    }

    var body: some View {
        let s = style.size
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            placeholderBackground
                            ProgressView()
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholderContent
                    @unknown default:
                        placeholderContent
                    }
                }
            } else {
                placeholderContent
            }
        }
        .frame(width: s.width, height: s.height)
        .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
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
