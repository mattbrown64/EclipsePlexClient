//
//  PlexHub.swift
//  EclipsePlexClient
//

import Foundation

/// One horizontal shelf from Plex hub APIs (`/hubs/sections/...`, `/hubs/metadata/.../related`).
nonisolated struct PlexHubShelf: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let hits: [PlexCatalogSearchHit]
}

// MARK: - Hub JSON (PMS)

nonisolated struct PlexHubsRoot: Decodable {
    let MediaContainer: PlexHubsContainer
}

nonisolated struct PlexHubsContainer: Decodable {
    private let Hub: PlexHubDTOList?

    var hubDTOs: [PlexHubDTO] {
        Hub?.values ?? []
    }
}

nonisolated struct PlexHubDTOList: Decodable {
    let values: [PlexHubDTO]

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var out: [PlexHubDTO] = []
            while !unkeyed.isAtEnd {
                out.append(try unkeyed.decode(PlexHubDTO.self))
            }
            self.values = out
            return
        }
        self.values = [try PlexHubDTO(from: decoder)]
    }
}

nonisolated struct PlexHubDTO: Decodable {
    let title: String?
    let hubKey: String?
    let key: String?
    let type: String?
    let size: Int?
    private let Metadata: PlexRecordList?
    private let Directory: PlexRecordList?

    enum CodingKeys: String, CodingKey {
        case title, hubKey, key, type, size, Metadata, Directory
    }

    var records: [PlexRecordDTO] {
        (Metadata?.values ?? []) + (Directory?.values ?? [])
    }

    var stableID: String {
        let k = hubKey ?? key ?? title ?? "hub"
        return k
    }
}
