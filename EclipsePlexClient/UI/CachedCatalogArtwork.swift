//
//  CachedCatalogArtwork.swift
//  EclipsePlexClient
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Loads artwork via `PlexArtworkCache` then falls back to network.
struct CachedCatalogArtwork: View {
    let url: URL
    let size: CGSize
    let cornerRadius: CGFloat

    @State private var loadedImage: PlexCachedImage?

    var body: some View {
        Group {
            if let loadedImage {
                #if canImport(UIKit)
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFill()
                #elseif canImport(AppKit)
                Image(nsImage: loadedImage)
                    .resizable()
                    .scaledToFill()
                #endif
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.quaternary.opacity(0.35))
                    ProgressView()
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) {
            if let cached = PlexArtworkCache.cachedImage(for: url) {
                loadedImage = cached
                return
            }
            guard let data = await PlexArtworkCache.fetchData(from: url) else { return }
            #if canImport(UIKit)
            loadedImage = UIImage(data: data)
            #elseif canImport(AppKit)
            loadedImage = NSImage(data: data)
            #endif
        }
    }
}
