//
//  PlexStringDecoding.swift
//  EclipsePlexClient
//

import Foundation

/// Decodes HTML/XML entities in Plex API text fields.
nonisolated enum PlexStringDecoding {

    /// Compiled once and reused — `NSRegularExpression(pattern:)` is non-trivial
    /// and this decoder runs on every attribute value parsed from Plex XML.
    private static let hexEntityRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "&#x([0-9A-Fa-f]+);", options: [])
    }()
    private static let decEntityRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "&#(\\d+);", options: [])
    }()

    static func decodeHTMLEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }

        var result = string

        if let hexRegex = hexEntityRegex {
            result = replaceNumericEntities(in: result, regex: hexRegex, radix: 16)
        }
        if let decRegex = decEntityRegex {
            result = replaceNumericEntities(in: result, regex: decRegex, radix: 10)
        }

        let named: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
        ]
        for (entity, character) in named {
            result = result.replacingOccurrences(of: entity, with: character)
        }

        return result
    }

    private static func replaceNumericEntities(
        in string: String,
        regex: NSRegularExpression,
        radix: Int
    ) -> String {
        let nsRange = NSRange(string.startIndex..., in: string)
        var result = string
        for match in regex.matches(in: string, range: nsRange).reversed() {
            guard match.numberOfRanges > 1,
                  let fullRange = Range(match.range(at: 0), in: result),
                  let numRange = Range(match.range(at: 1), in: result),
                  let value = Int(result[numRange], radix: radix),
                  let scalar = Unicode.Scalar(value)
            else { continue }
            result.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return result
    }
}
