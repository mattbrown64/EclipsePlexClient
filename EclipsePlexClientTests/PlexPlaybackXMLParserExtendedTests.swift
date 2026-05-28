//  PlexPlaybackXMLParserExtendedTests.swift
//  EclipsePlexClientTests
//

import Foundation
import CoreFoundation
import Testing
@testable import EclipsePlexClient

struct PlexPlaybackXMLParserExtendedTests {
    @Test func parseDecisionFindsTranscodePath() {
        let xml = """
        <MediaContainer>
        <Video ratingKey="1">
        <Media>
        <Part key="/library/parts/abc" />
        </Media>
        </Video>
        <Transcode key="/video/:/transcode/universal/start.mkv" />
        </MediaContainer>
        """
        let decision = PlexPlaybackXMLParser.parseDecision(xml)
        #expect(decision?.transcodeResourcePath?.contains("transcode") == true)
        #expect(decision?.partKey?.contains("/library/parts/") == true)
    }

    @Test func parseMetadataExtrasExtractsSize() {
        let xml = """
        <MediaContainer>
        <Video ratingKey="1">
        <Media width="1920" height="1080"><Part /></Media>
        </Video>
        </MediaContainer>
        """
        let extras = PlexPlaybackXMLParser.parseMetadataExtras(xml)
        #expect(extras.sourceVideoSize?.width == 1920)
        #expect(extras.sourceVideoSize?.height == 1080)
    }

    @Test func parseMetadataExtrasExtractsSubtitleStreams() {
        let xml = """
        <MediaContainer>
        <Video ratingKey="1">
        <Media>
        <Stream streamType="3" id="42" title="English" />
        </Media>
        </Video>
        </MediaContainer>
        """
        let extras = PlexPlaybackXMLParser.parseMetadataExtras(xml)
        #expect(extras.subtitleStreams.count == 1)
        #expect(extras.subtitleStreams[0].id == "42")
        #expect(extras.subtitleStreams[0].displayName == "English")
    }

    @Test func parseSourcesMarksIndirectMedia() {
        let xml = """
        <MediaContainer>
        <Video ratingKey="9" key="/library/metadata/9">
        <Media indirect="1"><Part key="/library/parts/indirect" /></Media>
        </Video>
        </MediaContainer>
        """
        let sources = PlexPlaybackXMLParser.parse(xml, ratingKey: "9")
        #expect(sources?.isIndirect == true)
    }

    @Test func parseMarkersCreditsType() {
        let xml = #"<Marker type="credits" startTimeOffset="1000" endTimeOffset="5000"/>"#
        let markers = PlexPlaybackXMLParser.parseMarkers(xml)
        #expect(markers.count == 1)
        #expect(markers[0].type == .credits)
    }

    @Test func parseSourcesReturnsMetadataPath() {
        let xml = """
        <MediaContainer>
        <Video ratingKey="12345" key="/library/metadata/12345">
        <Media index="0"><Part index="0" key="/library/parts/x" /></Media>
        </Video>
        </MediaContainer>
        """
        let sources = PlexPlaybackXMLParser.parse(xml, ratingKey: "12345")
        #expect(sources != nil)
        #expect(sources?.metadataPath.contains("12345") == true)
    }
}
