//
//  PlexLibrarySectionsDecodeTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct PlexLibrarySectionsDecodeTests {
    @Test func decodesLibrarySectionsDirectoryArray() throws {
        let json = """
        {"MediaContainer":{"size":2,"Directory":[
          {"key":"/library/sections/1","title":"Movies","type":"movie","thumb":"/:/resources/movie.png"},
          {"key":"/library/sections/2","title":"TV Shows","type":"show","thumb":"/:/resources/show.png"}
        ]}}
        """
        let data = try #require(json.data(using: .utf8))
        let root = try PlexNetworking.jsonDecoder.decode(PlexMediaRoot.self, from: data)
        #expect(root.MediaContainer.records.count == 2)
        #expect(root.MediaContainer.records[0].displayTitle == "Movies")
        #expect(root.MediaContainer.records[1].key == "/library/sections/2")
    }
}
