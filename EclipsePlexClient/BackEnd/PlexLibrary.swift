//
//  PlexLibrary.swift
//  EclipsePlexClient
//

import Foundation

// MARK: - Section type (Plex library section `type` codes)

nonisolated enum PlexSectionType: Hashable, Sendable {
    case movie
    case show
    case music
    case photo
    case other(Int)

    init(plexCode: Int) {
        switch plexCode {
        case 1: self = .movie
        case 2: self = .show
        case 8: self = .music
        case 13: self = .photo
        default: self = .other(plexCode)
        }
    }

    var rawValue: Int {
        switch self {
        case .movie: return 1
        case .show: return 2
        case .music: return 8
        case .photo: return 13
        case .other(let code): return code
        }
    }
}

// MARK: - Library section

/// One Plex library section (`/library/sections`).
/// `thumbPath` / `compositePath` are server-relative; resolve with base URL and token when networking exists.
nonisolated struct PlexLibrary: Identifiable, Hashable, Sendable, Codable {
    var serverId: UUID?

    let sectionKey: String
    let title: String
    let type: Int

    let thumbPath: String?
    let compositePath: String?

    let uuid: String?
    let agent: String?
    let scanner: String?
    let language: String?
    /// Plex library default sort (`titleSort`, `addedAt:desc`, etc.) from section `sort`.
    let plexDefaultSortKey: String?

    var sectionType: PlexSectionType {
        PlexSectionType(plexCode: type)
    }

    /// Numeric section id for API paths (e.g. `1`), even when Plex `key` is `/library/sections/1`.
    var sectionID: String {
        Self.normalizeSectionKey(sectionKey)
    }

    /// `true` when `sectionID` matches a metadata `librarySectionID` from Plex.
    func matchesLibrarySectionID(_ sectionID: String?) -> Bool {
        guard let sectionID, !sectionID.isEmpty else { return false }
        return Self.normalizeSectionKey(sectionID) == self.sectionID
    }

    /// Strips `/library/sections/` prefixes so paths use a single numeric id.
    static func normalizeSectionKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: "/library/sections/") {
            let suffix = trimmed[range.upperBound...]
            if let first = suffix.split(separator: "/").first {
                return String(first)
            }
        }
        if trimmed.hasPrefix("/") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    var id: String {
        if let serverId {
            "\(serverId.uuidString):\(sectionKey)"
        } else {
            "unscoped:\(sectionKey)"
        }
    }

    enum CodingKeys: String, CodingKey {
        case sectionKey = "key"
        case title
        case type
        case thumbPath = "thumb"
        case compositePath = "composite"
        case uuid
        case agent
        case scanner
        case language
        case serverId
        case plexDefaultSortKey = "sort"
    }

    init(
        serverId: UUID? = nil,
        sectionKey: String,
        title: String,
        type: Int,
        thumbPath: String? = nil,
        compositePath: String? = nil,
        uuid: String? = nil,
        agent: String? = nil,
        scanner: String? = nil,
        language: String? = nil,
        plexDefaultSortKey: String? = nil
    ) {
        self.serverId = serverId
        self.sectionKey = sectionKey
        self.title = title
        self.type = type
        self.thumbPath = thumbPath
        self.compositePath = compositePath
        self.uuid = uuid
        self.agent = agent
        self.scanner = scanner
        self.language = language
        self.plexDefaultSortKey = plexDefaultSortKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serverId = try c.decodeIfPresent(UUID.self, forKey: .serverId)
        sectionKey = try c.decode(String.self, forKey: .sectionKey)
        title = try c.decode(String.self, forKey: .title)

        if let typeInt = try? c.decode(Int.self, forKey: .type) {
            type = typeInt
        } else if let typeString = try? c.decode(String.self, forKey: .type), let parsed = Int(typeString) {
            type = parsed
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: c,
                debugDescription: "Expected Int or numeric String for type"
            )
        }

        thumbPath = try c.decodeIfPresent(String.self, forKey: .thumbPath)
        compositePath = try c.decodeIfPresent(String.self, forKey: .compositePath)
        uuid = try c.decodeIfPresent(String.self, forKey: .uuid)
        agent = try c.decodeIfPresent(String.self, forKey: .agent)
        scanner = try c.decodeIfPresent(String.self, forKey: .scanner)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        plexDefaultSortKey = try c.decodeIfPresent(String.self, forKey: .plexDefaultSortKey)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(serverId, forKey: .serverId)
        try c.encode(sectionKey, forKey: .sectionKey)
        try c.encode(title, forKey: .title)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(thumbPath, forKey: .thumbPath)
        try c.encodeIfPresent(compositePath, forKey: .compositePath)
        try c.encodeIfPresent(uuid, forKey: .uuid)
        try c.encodeIfPresent(agent, forKey: .agent)
        try c.encodeIfPresent(scanner, forKey: .scanner)
        try c.encodeIfPresent(language, forKey: .language)
        try c.encodeIfPresent(plexDefaultSortKey, forKey: .plexDefaultSortKey)
    }

    func withServerId(_ id: UUID) -> PlexLibrary {
        var copy = self
        copy.serverId = id
        return copy
    }
}
