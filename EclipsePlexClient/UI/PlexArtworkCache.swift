//
//  PlexArtworkCache.swift
//  EclipsePlexClient
//
//  Two-tier artwork cache (in-memory `NSCache` + on-disk Data) with off-main
//  ImageIO downsampling. Posters never get decoded full-size on the main
//  thread, and cache hits return raw bytes — no PNG/JPEG round-trip.
//

import Foundation
import ImageIO
import OSLog

#if canImport(UIKit)
import UIKit
typealias PlexCachedImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlexCachedImage = NSImage
#endif

nonisolated enum PlexArtworkCache {
    private static let subdirectory = "PlexArtworkCache"
    /// Serializes disk reads/writes so ImageIO never decodes bytes while an
    /// atomic cache write is replacing the same file (malloc abort).
    private static let diskLock = NSLock()
    /// ImageIO is not reliably re-entrant; one decode at a time avoids heap
    /// corruption when detail artwork and playback startup overlap.
    private static let decodeLock = NSLock()

    /// Decoded images keyed by `"<url>|<maxPixelSize>"` so the same poster at
    /// different display sizes share storage but don't fight for slots.
    private static let memoryCache: NSCache<NSString, PlexCachedImage> = {
        let cache = NSCache<NSString, PlexCachedImage>()
        // ~64 MB; entries report cost via their pixel footprint estimate.
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    // MARK: - In-memory layer

    static func memoryImage(for url: URL, maxPixelSize: CGFloat) -> PlexCachedImage? {
        memoryCache.object(forKey: memoryKey(url: url, maxPixelSize: maxPixelSize) as NSString)
    }

    private static func storeInMemory(_ image: PlexCachedImage, for url: URL, maxPixelSize: CGFloat) {
        let key = memoryKey(url: url, maxPixelSize: maxPixelSize) as NSString
        memoryCache.setObject(image, forKey: key, cost: imageCost(image))
    }

    private static func memoryKey(url: URL, maxPixelSize: CGFloat) -> String {
        "\(url.absoluteString)|\(Int(maxPixelSize.rounded()))"
    }

    private static func imageCost(_ image: PlexCachedImage) -> Int {
        let size = image.size
        let scale: CGFloat
        #if canImport(UIKit)
        scale = image.scale
        #else
        scale = 1
        #endif
        let pixels = Int(size.width * scale) * Int(size.height * scale)
        return max(1, pixels * 4)
    }

    // MARK: - Disk layer

    /// Synchronous disk read returning the raw bytes Plex sent us. Callers should
    /// invoke from a background thread; SwiftUI `.task` already gives us that.
    ///
    /// Note: this returns a *heap copy* of the file contents, not a mapped view.
    /// A previous version used `.mappedIfSafe`, but the cache also writes new
    /// data via `store(data:for:)` atomically (rename-over) which swaps the
    /// inode while `CGImageSourceCreateWithData` may still be reading from
    /// the old mapped pages — producing the "freed pointer was not the last
    /// allocation" malloc abort during fast scroll / navigation.
    static func diskCachedData(for url: URL) -> Data? {
        diskLock.lock()
        defer { diskLock.unlock() }
        let file = fileURL(for: url)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try? Data(contentsOf: file)
    }

    static func store(data: Data, for url: URL) {
        diskLock.lock()
        defer { diskLock.unlock() }
        let file = fileURL(for: url)
        let dir = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    static func fetchData(from url: URL) async -> Data? {
        if let cached = diskCachedData(for: url) {
            return cached
        }
        do {
            let (data, response) = try await PlexNetworking.session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                return nil
            }
            store(data: data, for: url)
            return data
        } catch {
            return nil
        }
    }

    static func clearAll() {
        memoryCache.removeAllObjects()
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent(subdirectory, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Downsampling pipeline

    /// Background-priority load that hits memory → disk → network and decodes
    /// to a thumbnail no larger than `maxPixelSize` so list/grid cells don't
    /// drag full posters through the GPU.
    static func loadDownsampledImage(url: URL, maxPixelSize: CGFloat) async -> PlexCachedImage? {
        if let cached = memoryImage(for: url, maxPixelSize: maxPixelSize) {
            return cached
        }
        let state = AppSignposts.signposter.beginInterval("artwork.load")
        defer { AppSignposts.signposter.endInterval("artwork.load", state) }

        let result: PlexCachedImage? = await Task.detached(priority: .userInitiated) {
            if Task.isCancelled { return nil }
            if let data = diskCachedData(for: url) {
                if Task.isCancelled { return nil }
                if let image = downsampledImage(from: data, maxPixelSize: maxPixelSize) {
                    return image
                }
            }
            if Task.isCancelled { return nil }
            guard let data = await fetchData(from: url) else { return nil }
            if Task.isCancelled { return nil }
            return downsampledImage(from: data, maxPixelSize: maxPixelSize)
        }.value

        if Task.isCancelled { return nil }
        if let result {
            storeInMemory(result, for: url, maxPixelSize: maxPixelSize)
        }
        return result
    }

    /// Synchronous downsample. Call from a background thread/task.
    static func downsampledImage(from data: Data, maxPixelSize: CGFloat) -> PlexCachedImage? {
        decodeLock.lock()
        defer { decodeLock.unlock() }
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cgImage, size: .zero)
        #else
        return nil
        #endif
    }

    // MARK: - File layout

    private static func fileURL(for url: URL) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent(subdirectory, isDirectory: true)
        let name = url.absoluteString.data(using: .utf8)!
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
        return folder.appendingPathComponent(name)
    }
}
