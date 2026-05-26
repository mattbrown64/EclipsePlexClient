//
//  PlexArtworkCache.swift
//  EclipsePlexClient
//

import Foundation

#if canImport(UIKit)
import UIKit
typealias PlexCachedImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlexCachedImage = NSImage
#endif

/// Disk cache for Plex poster URLs (keyed by absolute artwork URL).
enum PlexArtworkCache {
    private static let subdirectory = "PlexArtworkCache"

    static func cachedImage(for url: URL) -> PlexCachedImage? {
        let file = fileURL(for: url)
        guard FileManager.default.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file)
        else { return nil }
        #if canImport(UIKit)
        return UIImage(data: data)
        #elseif canImport(AppKit)
        return NSImage(data: data)
        #else
        return nil
        #endif
    }

    static func store(data: Data, for url: URL) {
        let file = fileURL(for: url)
        let dir = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    static func fetchData(from url: URL) async -> Data? {
        if let cached = cachedImage(for: url) {
            #if canImport(UIKit)
            return cached.pngData() ?? cached.jpegData(compressionQuality: 0.92)
            #elseif canImport(AppKit)
            guard let tiff = cached.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
            else { return nil }
            return jpeg
            #else
            return nil
            #endif
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
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
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent(subdirectory, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
    }

    private static func fileURL(for url: URL) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent(subdirectory, isDirectory: true)
        let name = url.absoluteString.data(using: .utf8)!
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
        return folder.appendingPathComponent(name)
    }
}
