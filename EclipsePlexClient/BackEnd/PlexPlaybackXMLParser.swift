//
//  PlexPlaybackXMLParser.swift
//  EclipsePlexClient
//

import CoreGraphics
import Foundation

/// Plex JSON metadata often omits `Media`/`Part`; XML includes them for stream URLs.
nonisolated enum PlexPlaybackXMLParser {

    /// Compiled-regex cache. `NSRegularExpression(pattern:)` runs a real parser
    /// and is significantly more expensive than a match — this XML parser is
    /// invoked on every metadata fetch with the same handful of patterns, so
    /// caching the compiled form per pattern string is a meaningful win.
    /// `NSCache` is thread-safe and self-evicting under memory pressure.
    private static let regexCache: NSCache<NSString, NSRegularExpression> = {
        let cache = NSCache<NSString, NSRegularExpression>()
        cache.countLimit = 64
        return cache
    }()

    private static func cachedRegex(_ pattern: String) -> NSRegularExpression? {
        let key = pattern as NSString
        if let cached = regexCache.object(forKey: key) { return cached }
        guard let compiled = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        regexCache.setObject(compiled, forKey: key)
        return compiled
    }

    nonisolated struct Sources: Sendable {
        let metadataPath: String
        let partKey: String?
        let mediaIndex: Int
        let partIndex: Int
        /// Remote/indirect libraries cannot be fetched at the part URL on this server.
        let isIndirect: Bool
    }

    static func parse(_ xml: String, ratingKey: String) -> Sources? {
        let metadataPath =
            firstCapture(#"<(?:Video|Movie|Episode|Track)[^>]*\bkey="(/library/metadata/\d+)"#, in: xml)
            ?? "/library/metadata/\(ratingKey)"

        let partKeys = allCaptures(#"<Part[^>]*\bkey="([^"]+)"#, in: xml)
            .filter { $0.contains("/library/parts/") }

        let isIndirect = xml.range(
            of: #"<Media[^>]*\bindirect="1""#,
            options: .regularExpression
        ) != nil

        let mediaIndex: Int
        if let firstPart = partKeys.first, let partRange = xml.range(of: firstPart) {
            let prefix = String(xml[..<partRange.lowerBound])
            let mediaCount = countMatches(#"<Media\b"#, in: prefix)
            mediaIndex = max(0, mediaCount - 1)
        } else {
            mediaIndex = 0
        }

        return Sources(
            metadataPath: metadataPath,
            partKey: partKeys.first,
            mediaIndex: max(0, mediaIndex),
            partIndex: 0,
            isIndirect: isIndirect
        )
    }

    nonisolated struct Decision: Sendable {
        let partKey: String?
        /// e.g. `/video/:/transcode/universal/start.m3u8?...`
        let transcodeResourcePath: String?
    }

    nonisolated struct MetadataExtras: Sendable {
        let subtitleStreams: [PlexSubtitleStream]
        let sourceVideoSize: CGSize?
    }

    static func parseMetadataExtras(_ xml: String) -> MetadataExtras {
        var streams: [PlexSubtitleStream] = []
        if let regex = cachedRegex(#"<Stream[^>]*streamType="3"[^>]*\bid="(\d+)"[^>]*>"#) {
            let range = NSRange(xml.startIndex..., in: xml)
            for match in regex.matches(in: xml, range: range) {
                guard match.numberOfRanges > 1,
                      let idRange = Range(match.range(at: 1), in: xml),
                      let fullRange = Range(match.range, in: xml) else { continue }
                let id = String(xml[idRange])
                let snippet = String(xml[fullRange])
                let title = firstCapture(#"(?:title|language)="([^"]+)""#, in: snippet) ?? "Subtitle"
                streams.append(PlexSubtitleStream(id: id, displayName: title))
            }
        }

        let width = firstCapture(#"<Media[^>]*\bwidth="(\d+)""#, in: xml).flatMap(Int.init)
        let height = firstCapture(#"<Media[^>]*\bheight="(\d+)""#, in: xml).flatMap(Int.init)
        let size: CGSize?
        if let width, let height, width > 0, height > 0 {
            size = CGSize(width: width, height: height)
        } else {
            size = nil
        }
        return MetadataExtras(subtitleStreams: streams, sourceVideoSize: size)
    }

    /// Intro/credits markers are present in metadata XML but often missing from JSON.
    static func parseMarkers(_ xml: String) -> [PlexPlaybackMarker] {
        guard let regex = cachedRegex(#"<Marker\b[^>]*>"#) else {
            return []
        }
        let range = NSRange(xml.startIndex..., in: xml)
        return regex.matches(in: xml, range: range).compactMap { match in
            guard let tagRange = Range(match.range, in: xml) else { return nil }
            return parseMarkerTag(String(xml[tagRange]))
        }
    }

    private static func parseMarkerTag(_ tag: String) -> PlexPlaybackMarker? {
        guard let typeRaw = firstCapture(#"\btype="([^"]+)""#, in: tag) else { return nil }
        let start = markerOffset(named: "startTimeOffset", in: tag)
            ?? markerOffset(named: "startOffset", in: tag)
            ?? 0
        guard let end = markerOffset(named: "endTimeOffset", in: tag)
            ?? markerOffset(named: "endOffset", in: tag),
              end > start
        else { return nil }
        let records = [PlexMarkerRecord(type: typeRaw, startTimeOffset: start, endTimeOffset: end)]
        return PlexPlaybackMarkerParser.markers(from: records).first
    }

    private static func markerOffset(named name: String, in tag: String) -> Int? {
        firstCapture(
            #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"="(\d+)""#,
            in: tag
        ).flatMap(Int.init)
    }

    static func parseDecision(_ xml: String) -> Decision? {
        let transcodePath = firstCapture(#"\bkey="(/video/:/transcode/[^"]+)""#, in: xml)
        let partKey = allCaptures(#"<Part[^>]*\bkey="([^"]+)"#, in: xml)
            .first { $0.contains("/library/parts/") }
        guard transcodePath != nil || partKey != nil else { return nil }
        return Decision(partKey: partKey, transcodeResourcePath: transcodePath)
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = cachedRegex(pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    private static func countMatches(_ pattern: String, in text: String) -> Int {
        guard let regex = cachedRegex(pattern) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func allCaptures(_ pattern: String, in text: String) -> [String] {
        guard let regex = cachedRegex(pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }

}
