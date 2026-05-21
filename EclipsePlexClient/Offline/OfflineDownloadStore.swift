//
//  OfflineDownloadStore.swift
//  EclipsePlexClient
//

import Foundation

enum OfflineDownloadStore {
    private static let fileName = "offlineDownloads.v1.json"

    static func load() -> [OfflineDownloadRecord] {
        guard let url = storeURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([OfflineDownloadRecord].self, from: data)
        else { return [] }
        return decoded
    }

    static func save(_ records: [OfflineDownloadRecord]) {
        guard let url = storeURL else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static var downloadsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("EclipsePlexDownloads", isDirectory: true)
    }

    private static var storeURL: URL? {
        let dir = downloadsDirectory
        return dir.appendingPathComponent(fileName)
    }
}
