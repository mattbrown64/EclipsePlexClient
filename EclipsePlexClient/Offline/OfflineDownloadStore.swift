//
//  OfflineDownloadStore.swift
//  EclipsePlexClient
//

import Foundation

enum OfflineDownloadStoreError: LocalizedError {
    case missingStoreURL
    case encodeFailed
    case writeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .missingStoreURL: return "Could not locate offline download storage."
        case .encodeFailed: return "Could not save download list."
        case .writeFailed(let underlying): return "Could not write downloads: \(underlying.localizedDescription)"
        }
    }
}

nonisolated enum OfflineDownloadStore {
    private static let fileName = "offlineDownloads.v1.json"

    static func load() -> [OfflineDownloadRecord] {
        guard let url = storeURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([OfflineDownloadRecord].self, from: data)
        else { return [] }
        return decoded
    }

    static func save(_ records: [OfflineDownloadRecord]) throws {
        guard let url = storeURL else { throw OfflineDownloadStoreError.missingStoreURL }
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(records) else {
            throw OfflineDownloadStoreError.encodeFailed
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw OfflineDownloadStoreError.writeFailed(underlying: error)
        }
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
