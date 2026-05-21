//
//  PlexPlaybackMarker.swift
//  EclipsePlexClient
//

import Foundation

nonisolated enum PlexMarkerType: String, Sendable {
    case intro
    case credits
    case commercial
    case unknown
}

nonisolated struct PlexPlaybackMarker: Sendable, Hashable {
    let type: PlexMarkerType
    let startMs: Int
    let endMs: Int

    func contains(positionMs: Int) -> Bool {
        positionMs >= startMs && positionMs < endMs
    }

    /// Whether the skip chip should be offered at `positionMs`.
    func isSkippable(at positionMs: Int) -> Bool {
        guard type != .unknown, endMs > startMs else { return false }
        switch type {
        case .intro:
            return positionMs < endMs && positionMs >= startMs - 10_000
        case .credits, .commercial:
            return contains(positionMs: positionMs)
        case .unknown:
            return false
        }
    }
}

nonisolated enum PlexPlaybackMarkerParser {
    static func markers(from records: [PlexMarkerRecord]) -> [PlexPlaybackMarker] {
        records.compactMap { record in
            guard let end = record.endTimeOffset, end > 0 else { return nil }
            let start = record.startTimeOffset ?? 0
            let type = markerType(from: record.type ?? "")
            guard type != .unknown else { return nil }
            return PlexPlaybackMarker(type: type, startMs: start, endMs: end)
        }
    }

    /// Prefer XML markers; merge JSON when it adds more; normalize units against duration.
    static func merged(
        xml: [PlexPlaybackMarker],
        json: [PlexPlaybackMarker],
        durationMs: Int?
    ) -> [PlexPlaybackMarker] {
        let combined = xml + json
        var seen = Set<String>()
        let unique = combined.filter { marker in
            let key = "\(marker.type.rawValue)|\(marker.startMs)|\(marker.endMs)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
        return normalize(unique, durationMs: durationMs)
    }

    static func activeMarker(at positionMs: Int, in markers: [PlexPlaybackMarker]) -> PlexPlaybackMarker? {
        markers
            .filter { $0.isSkippable(at: positionMs) }
            .max(by: { $0.startMs < $1.startMs })
    }

    static func normalize(_ markers: [PlexPlaybackMarker], durationMs: Int?) -> [PlexPlaybackMarker] {
        markers.compactMap { normalize($0, durationMs: durationMs) }
    }

    private static func normalize(_ marker: PlexPlaybackMarker, durationMs: Int?) -> PlexPlaybackMarker? {
        var start = marker.startMs
        var end = marker.endMs
        if let durationMs, durationMs > 0, end > 0, end < 10_000, durationMs > end * 50 {
            start *= 1000
            end *= 1000
        }
        guard end > start else { return nil }
        return PlexPlaybackMarker(type: marker.type, startMs: start, endMs: end)
    }

    private static func markerType(from raw: String) -> PlexMarkerType {
        switch raw.lowercased() {
        case "intro", "intro_start": .intro
        case "credits", "credit", "endscene": .credits
        case "commercial": .commercial
        default: .unknown
        }
    }
}

/// Decoded from Plex metadata `Marker` elements.
nonisolated struct PlexMarkerRecord: Decodable, Sendable {
    let type: String?
    let startTimeOffset: Int?
    let endTimeOffset: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case startTimeOffset
        case endTimeOffset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        startTimeOffset = Self.flexInt(container, key: .startTimeOffset)
        endTimeOffset = Self.flexInt(container, key: .endTimeOffset)
    }

    init(type: String?, startTimeOffset: Int?, endTimeOffset: Int?) {
        self.type = type
        self.startTimeOffset = startTimeOffset
        self.endTimeOffset = endTimeOffset
    }

    private static func flexInt(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        if let text = try? container.decode(String.self, forKey: key) {
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}
