//
//  PlexPrefsXMLParser.swift
//  EclipsePlexClient
//

import Foundation

/// Parses Plex server preferences (`GET /:/prefs`).
nonisolated enum PlexPrefsXMLParser {

    static func parseSettings(_ xml: String) -> [String: String] {
        let pattern = "<Setting\\b([^>]*)(?:/>|>)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [:] }
        let range = NSRange(xml.startIndex..., in: xml)
        var out: [String: String] = [:]
        for match in regex.matches(in: xml, range: range) {
            guard match.numberOfRanges > 1,
                  let attrRange = Range(match.range(at: 1), in: xml) else { continue }
            let attrs = String(xml[attrRange])
            guard let id = attribute("id", in: attrs) else { continue }
            let value = attribute("value", in: attrs) ?? ""
            out[id] = value
        }
        return out
    }

    static func identityVersion(in xml: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<MediaContainer[^>]*\bversion="([^"]*)""#, options: []),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: xml)
        else { return nil }
        let value = String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func serverStatus(
        from prefs: [String: String],
        identityName: String?,
        identityVersion: String?
    ) -> PlexServerStatusInfo {
        PlexServerStatusInfo(
            friendlyName: identityName ?? prefs["FriendlyName"],
            version: identityVersion ?? prefs["LastAutomaticVersion"] ?? prefs["ManualVersion"],
            platform: prefs["Platform"],
            publishToPlex: boolPref(prefs["PublishServerOnPlex"]),
            secureConnections: prefs["secureConnections"],
            relayEnabled: boolPref(prefs["RelayEnabled"]),
            manualPortMapping: boolPref(prefs["ManualPortMappingMode"])
        )
    }

    private static func boolPref(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
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
