//
//  PlexRecordDecodingTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct PlexRecordDecodingTests {
    @Test func recordListDecodesSingleObject() throws {
        let json = """
        {"ratingKey":"1","title":"Film","type":1}
        """
        let list = try JSONDecoder().decode(PlexRecordList.self, from: Data(json.utf8))
        #expect(list.values.count == 1)
        #expect(list.values[0].ratingKey == "1")
    }

    @Test func recordListDecodesArray() throws {
        let json = """
        [{"ratingKey":"1","title":"A","type":1},{"ratingKey":"2","title":"B","type":1}]
        """
        let list = try JSONDecoder().decode(PlexRecordList.self, from: Data(json.utf8))
        #expect(list.values.count == 2)
    }

    @Test func typeFieldDecodesIntOrString() throws {
        let intJSON = Data("1".utf8)
        let strJSON = Data(#""movie""#.utf8)
        let intField = try JSONDecoder().decode(PlexTypeField.self, from: intJSON)
        let strField = try JSONDecoder().decode(PlexTypeField.self, from: strJSON)
        if case .int(1) = intField { #expect(Bool(true)) } else { Issue.record("Expected int type")
        }
        if case .string("movie") = strField { #expect(Bool(true)) } else { Issue.record("Expected string type")
        }
    }
}

struct PlexSectionTypeTests {
    @Test func plexCodesMapToSectionTypes() {
        #expect(PlexSectionType(plexCode: 1) == .movie)
        #expect(PlexSectionType(plexCode: 2) == .show)
        #expect(PlexSectionType(plexCode: 8) == .music)
        #expect(PlexSectionType(plexCode: 13) == .photo)
        if case .other(99) = PlexSectionType(plexCode: 99) {
            #expect(PlexSectionType(plexCode: 99).rawValue == 99)
        } else {
            Issue.record("Expected .other(99)")
        }
    }
}
