//
//  PlexAccountsXMLParser.swift
//  EclipsePlexClient
//

import Foundation

/// Parses Plex home users (`GET /accounts`).
nonisolated enum PlexAccountsXMLParser {

    static func parse(_ xml: String) -> [PlexServerUser] {
        let pattern = "<User\\b([^>]*)(?:/>|>)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(xml.startIndex..., in: xml)
        var out: [PlexServerUser] = []
        for match in regex.matches(in: xml, range: range) {
            guard match.numberOfRanges > 1,
                  let attrRange = Range(match.range(at: 1), in: xml) else { continue }
            let attrs = String(xml[attrRange])
            guard let id = attribute("id", in: attrs) ?? attribute("key", in: attrs) else { continue }
            let title = attribute("title", in: attrs)
                ?? attribute("name", in: attrs)
                ?? attribute("username", in: attrs)
                ?? "User \(id)"
            let admin = attribute("admin", in: attrs) == "1"
            let managed = attribute("restricted", in: attrs) == "1"
                || attribute("managed", in: attrs) == "1"
            out.append(
                PlexServerUser(
                    id: id,
                    title: title,
                    thumbPath: attribute("thumb", in: attrs),
                    isAdmin: admin,
                    isManaged: managed
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
}
