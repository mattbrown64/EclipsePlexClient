//
//  PlexMediaServerClient+Extras.swift
//  EclipsePlexClient
//

import Foundation

nonisolated struct PlexExtraItem: Identifiable, Hashable, Sendable {
    let ratingKey: String
    let title: String
    let extraType: String?
    let thumbPath: String?

    var id: String { ratingKey }

    var displayType: String {
        switch extraType?.lowercased() {
        case "trailer": return "Trailer"
        case "deletedscene": return "Deleted scene"
        case "behindthescenes": return "Behind the scenes"
        case "interview": return "Interview"
        case "scene": return "Scene"
        default: return extraType?.capitalized ?? "Extra"
        }
    }
}

nonisolated struct PlexRelatedItem: Identifiable, Hashable, Sendable {
    let ratingKey: String
    let title: String
    let thumbPath: String?
    let librarySectionID: String?

    var id: String { ratingKey }
}

extension PlexMediaServerClient {
    func fetchExtras(ratingKey: String) async throws -> [PlexExtraItem] {
        let rows = try await fetchAllRecords(
            path: "/library/metadata/\(ratingKey)/children",
            extraQuery: [URLQueryItem(name: "excludeAllLeaves", value: "1")]
        )
        return rows.compactMap { row in
            guard let key = row.ratingKey else { return nil }
            let kind = PlexKind(plexTypeField: row.type)
            switch kind {
            case .show, .season, .episode, .artist, .album, .track: return nil
            default: break
            }
            let typeLabel: String? = {
                if case .string(let s) = row.type { return s }
                return nil
            }()
            return PlexExtraItem(
                ratingKey: key,
                title: row.displayTitle,
                extraType: typeLabel,
                thumbPath: row.thumb
            )
        }
    }

    func fetchRelatedItems(ratingKey: String) async throws -> [PlexRelatedItem] {
        let path = "/library/metadata/\(ratingKey)/related"
        let rows = (try? await fetchAllRecords(path: path)) ?? []
        return rows.compactMap { row in
            guard let key = row.ratingKey else { return nil }
            return PlexRelatedItem(
                ratingKey: key,
                title: row.displayTitle,
                thumbPath: row.thumb,
                librarySectionID: row.librarySectionID
            )
        }
    }
}
