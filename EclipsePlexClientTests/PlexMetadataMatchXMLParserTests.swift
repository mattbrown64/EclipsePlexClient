//  PlexMetadataMatchXMLParserTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct PlexMetadataMatchXMLParserTests {
    @Test func parsesSearchResultCandidates() {
        let xml = """
        <MediaContainer size="2">
          <SearchResult guid="com.plexapp.agents.imdb://tt0137523?lang=en" name="Fight Club" year="1999"
            summary="An insomniac office worker..." thumb="/library/metadata/1001/thumb/1" />
          <SearchResult guid="com.plexapp.agents.themoviedb://550?lang=en" name="Fight Club" year="1999" />
        </MediaContainer>
        """
        let matches = PlexMetadataMatchXMLParser.parse(xml)
        #expect(matches.count == 2)
        #expect(matches[0].title == "Fight Club")
        #expect(matches[0].year == 1999)
        #expect(matches[0].guid.contains("imdb"))
    }

    @Test func decodesHTMLEntitiesInMatchText() {
        let xml = """
        <MediaContainer size="1">
          <SearchResult guid="guid-1" name="&#12304;OSHI NO KO&#12305;" year="2023"
            summary="who&#39;s the villain" />
        </MediaContainer>
        """
        let matches = PlexMetadataMatchXMLParser.parse(xml)
        #expect(matches.count == 1)
        #expect(matches[0].title == "【OSHI NO KO】")
        #expect(matches[0].summary == "who's the villain")
    }
}
