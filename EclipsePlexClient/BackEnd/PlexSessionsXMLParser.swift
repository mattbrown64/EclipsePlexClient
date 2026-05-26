//
//  PlexSessionsXMLParser.swift
//  EclipsePlexClient
//

import Foundation

/// Parses Plex `/status/sessions` XML into display models.
nonisolated enum PlexSessionsXMLParser {

    static func parse(_ xml: String) -> [PlexActiveSession] {
        let tags = ["Video", "Track", "Photo"]
        var sessions: [PlexActiveSession] = []
        for tag in tags {
            sessions.append(contentsOf: parseElements(tag: tag, in: xml))
        }
        return sessions
    }

    private static func parseElements(tag: String, in xml: String) -> [PlexActiveSession] {
        let pattern = "<\(tag)\\b([^>]*)(?:/>|>)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(xml.startIndex..., in: xml)
        var out: [PlexActiveSession] = []
        for match in regex.matches(in: xml, range: range) {
            guard match.numberOfRanges > 1,
                  let attrRange = Range(match.range(at: 1), in: xml),
                  let fullRange = Range(match.range(at: 0), in: xml) else { continue }
            let attrs = String(xml[attrRange])
            let nestedSessionId = sessionId(near: fullRange.upperBound, in: xml)
            guard let session = mapSession(tag: tag, attributes: attrs, nestedSessionId: nestedSessionId)
            else { continue }
            out.append(session)
        }
        return out
    }

    private static func sessionId(near index: String.Index, in xml: String) -> String? {
        let end = xml.index(index, offsetBy: 4_096, limitedBy: xml.endIndex) ?? xml.endIndex
        let slice = String(xml[index ..< end])
        guard let regex = try? NSRegularExpression(pattern: #"<Session[^>]*\bid="([^"]*)""#, options: []) else {
            return nil
        }
        guard let match = regex.firstMatch(in: slice, range: NSRange(slice.startIndex..., in: slice)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: slice)
        else { return nil }
        let value = String(slice[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func mapSession(
        tag: String,
        attributes: String,
        nestedSessionId: String?
    ) -> PlexActiveSession? {
        let title = attribute("title", in: attributes)
            ?? attribute("grandparentTitle", in: attributes)
            ?? "Unknown"
        let sessionKey = attribute("sessionKey", in: attributes)
            ?? attribute("key", in: attributes)
        let terminateSessionId = nestedSessionId ?? sessionKey ?? UUID().uuidString
        let stableID = sessionKey ?? terminateSessionId

        let show = attribute("grandparentTitle", in: attributes)
        let season = attribute("parentTitle", in: attributes)
        var subtitleParts: [String] = []
        if let show, !show.isEmpty, show != title { subtitleParts.append(show) }
        if let season, !season.isEmpty { subtitleParts.append(season) }
        let subtitle = subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · ")

        let userName = attribute("user", in: attributes)
            ?? nestedUserTitle(in: attributes)
        let player = attribute("player", in: attributes)
        let state = attribute("state", in: attributes)
        let viewOffset = attributeInt("viewOffset", in: attributes)
        let duration = attributeInt("duration", in: attributes)

        let kindLabel: String
        switch tag {
        case "Track": kindLabel = "Music"
        case "Photo": kindLabel = "Photo"
        default: kindLabel = "Video"
        }

        return PlexActiveSession(
            id: stableID,
            terminateSessionId: terminateSessionId,
            title: title,
            subtitle: subtitle ?? kindLabel,
            userName: userName,
            player: player,
            state: state,
            viewOffsetMs: viewOffset,
            durationMs: duration
        )
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

    private static func nestedUserTitle(in attributes: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<User[^>]*\btitle="([^"]*)""#,
            options: []
        ),
              let match = regex.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: attributes)
        else { return nil }
        let value = String(attributes[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
