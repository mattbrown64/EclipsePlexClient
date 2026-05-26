//
//  PhotoSlideshowView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Full-screen photo slideshow for photo libraries.
struct PhotoSlideshowView: View {
    let plexServer: PlexServer
    let photos: [PlexCatalogNode]
    @State private var index: Int
    @Environment(\.dismiss) private var dismiss

    init(plexServer: PlexServer, photos: [PlexCatalogNode], startIndex: Int = 0) {
        self.plexServer = plexServer
        let filtered = photos.filter { node in
            if case .photo = node { return true }
            return false
        }
        self.photos = filtered
        _index = State(initialValue: min(max(0, startIndex), max(0, filtered.count - 1)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if photos.indices.contains(index), case .photo(let photo) = photos[index] {
                CatalogArtworkImage(
                    plexServer: plexServer,
                    thumbPath: photo.thumbPath,
                    style: .detailHero
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if photos.indices.contains(index) {
                        Text(photos[index].listTitle)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
                .padding()
                Spacer()
                HStack {
                    Button { step(-1) } label: { Image(systemName: "chevron.left.circle.fill").font(.largeTitle) }
                        .disabled(index <= 0)
                    Spacer()
                    Text("\(index + 1) / \(photos.count)")
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Button { step(1) } label: { Image(systemName: "chevron.right.circle.fill").font(.largeTitle) }
                        .disabled(index >= photos.count - 1)
                }
                .padding()
                .foregroundStyle(.white)
            }
        }
#if os(macOS)
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
#endif
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard photos.indices.contains(next) else { return }
        index = next
    }
}

struct PhotoSlideshowPresentation: ViewModifier {
    @Binding var isPresented: Bool
    let plexServer: PlexServer
    let photos: [PlexCatalogNode]
    let startIndex: Int

    func body(content: Content) -> some View {
        #if os(iOS) || os(tvOS)
        content.fullScreenCover(isPresented: $isPresented) {
            PhotoSlideshowView(plexServer: plexServer, photos: photos, startIndex: startIndex)
        }
        #else
        content.sheet(isPresented: $isPresented) {
            PhotoSlideshowView(plexServer: plexServer, photos: photos, startIndex: startIndex)
                .frame(minWidth: 720, minHeight: 480)
        }
        #endif
    }
}
