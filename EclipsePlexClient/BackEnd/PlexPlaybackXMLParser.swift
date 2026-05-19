//
//  PlexPlaybackXMLParser.swift
//  EclipsePlexClient
//

import Foundation

/// Plex JSON metadata often omits `Media`/`Part`; XML includes them for stream URLs.
nonisolated enum PlexPlaybackXMLParser {

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

    static func parseDecision(_ xml: String) -> Decision? {
        let transcodePath = firstCapture(#"\bkey="(/video/:/transcode/[^"]+)""#, in: xml)
        let partKey = allCaptures(#"<Part[^>]*\bkey="([^"]+)"#, in: xml)
            .first { $0.contains("/library/parts/") }
        guard transcodePath != nil || partKey != nil else { return nil }
        return Decision(partKey: partKey, transcodeResourcePath: transcodePath)
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    private static func countMatches(_ pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func allCaptures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }

}
