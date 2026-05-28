//  PlexStringDecodingTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct PlexStringDecodingTests {
    @Test func decodesDecimalAndNamedEntities() {
        #expect(PlexStringDecoding.decodeHTMLEntities("Atom&#39;s Last Shot") == "Atom's Last Shot")
        #expect(PlexStringDecoding.decodeHTMLEntities("&#34;Pegasus, Inc.&#34;") == "\"Pegasus, Inc.\"")
        #expect(PlexStringDecoding.decodeHTMLEntities("a &amp; b") == "a & b")
    }

    @Test func decodesDecimalUnicodeEntities() {
        #expect(PlexStringDecoding.decodeHTMLEntities("&#12304;OSHI NO KO&#12305;") == "【OSHI NO KO】")
    }
}
