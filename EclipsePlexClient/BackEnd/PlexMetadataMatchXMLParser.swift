//
//  PlexMetadataMatchXMLParser.swift
//  EclipsePlexClient
//

import Foundation

/// Parses Plex metadata match results (`/library/metadata/{id}/matches`).
nonisolated enum PlexMetadataMatchXMLParser {

    static func parse(_ xml: String) -> [PlexMetadataMatchCandidate] {
        let fromSearchResults = parseElements(tag: "SearchResult", in: xml)
        if !fromSearchResults.isEmpty { return fromSearchResults }
        return parseElements(tag: "Video", in: xml) + parseElements(tag: "Movie", in: xml)
            + parseElements(tag: "Show", in: xml)
    }

    private static func parseElements(tag: String, in xml: String) -> [PlexMetadataMatchCandidate] {
        let pattern = "<\(tag)\\b([^>]*)(?:/>|>)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(xml.startIndex..., in: xml)
        var out: [PlexMetadataMatchCandidate] = []
        var seenGuids: Set<String> = []
        for match in regex.matches(in: xml, range: range) {
            guard match.numberOfRanges > 1,
                  let attrRange = Range(match.range(at: 1), in: xml) else { continue }
            let attrs = String(xml[attrRange])
            guard let guid = attribute("guid", in: attrs), !guid.isEmpty else { continue }
            guard seenGuids.insert(guid).inserted else { continue }
            let rawTitle = attribute("name", in: attrs)
                ?? attribute("title", in: attrs)
                ?? "Unknown"
            let title = PlexStringDecoding.decodeHTMLEntities(rawTitle)
            out.append(
                PlexMetadataMatchCandidate(
                    guid: guid,
                    title: title,
                    year: attributeInt("year", in: attrs),
                    summary: attribute("summary", in: attrs).map(PlexStringDecoding.decodeHTMLEntities),
                    thumbPath: attribute("thumb", in: attrs)
                )
            )
        }
        return out
    }

    private static func attribute(_ name: String, in attributes: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b\#(name)="([^"]*)""#,
            options: []
        ),
              let match = regex.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: attributes)
        else { return nil }
        let value = String(attributes[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func attributeInt(_ name: String, in attributes: String) -> Int? {
        guard let raw = attribute(name, in: attributes) else { return nil }
        return Int(raw)
    }
}
