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

/// Loads artwork through `PlexArtworkCache`'s memory → disk → network pipeline
/// and decodes it off-main at the cell's pixel size.
struct CachedCatalogArtwork: View {
    let url: URL
    let size: CGSize
    let cornerRadius: CGFloat

    @EnvironmentObject private var playbackPresenter: PlaybackPresenter
    @State private var loadedImage: PlexCachedImage?
    #if os(iOS) || os(tvOS)
    @Environment(\.displayScale) private var displayScale
    #endif

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
                placeholder
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) {
            guard playbackPresenter.activeRequest == nil else { return }
            await load()
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.quaternary.opacity(0.35))
            Image(systemName: "photo")
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
    }

    private var displayScaleValue: CGFloat {
        #if os(iOS) || os(tvOS)
        return max(1, displayScale)
        #else
        return 2
        #endif
    }

    private var maxPixelSize: CGFloat {
        let longestEdge = max(size.width, size.height)
        return max(64, ceil(longestEdge * displayScaleValue))
    }

    private func load() async {
        guard playbackPresenter.activeRequest == nil else { return }
        let maxPixel = maxPixelSize
        if let cached = PlexArtworkCache.memoryImage(for: url, maxPixelSize: maxPixel) {
            guard playbackPresenter.activeRequest == nil else { return }
            loadedImage = cached
            return
        }
        let image = await PlexArtworkCache.loadDownsampledImage(url: url, maxPixelSize: maxPixel)
        guard !Task.isCancelled, playbackPresenter.activeRequest == nil else { return }
        loadedImage = image
    }
}
