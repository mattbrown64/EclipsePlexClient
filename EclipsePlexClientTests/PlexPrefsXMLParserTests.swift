//  PlexPrefsXMLParserTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct PlexPrefsXMLParserTests {
    @Test func parsesSettingValues() {
        let xml = """
        <MediaContainer>
          <Setting id="PublishServerOnPlex" value="1" />
          <Setting id="RelayEnabled" value="0" />
          <Setting id="FriendlyName" value="NAS" />
        </MediaContainer>
        """
        let prefs = PlexPrefsXMLParser.parseSettings(xml)
        #expect(prefs["PublishServerOnPlex"] == "1")
        #expect(prefs["RelayEnabled"] == "0")
        #expect(prefs["FriendlyName"] == "NAS")
    }

    @Test func buildsServerStatusFromPrefs() {
        let prefs = [
            "PublishServerOnPlex": "1",
            "RelayEnabled": "true",
            "secureConnections": "required",
            "Platform": "Linux",
        ]
        let status = PlexPrefsXMLParser.serverStatus(
            from: prefs,
            identityName: "My Plex",
            identityVersion: "1.40.0"
        )
        #expect(status.friendlyName == "My Plex")
        #expect(status.version == "1.40.0")
        #expect(status.publishToPlex == true)
        #expect(status.relayEnabled == true)
        #expect(status.secureConnections == "required")
        #expect(status.platform == "Linux")
    }

    @Test func identityVersionFromXML() {
        let xml = #"<MediaContainer size="0" version="1.41.2.1234-abcdef" />"#
        #expect(PlexPrefsXMLParser.identityVersion(in: xml) == "1.41.2.1234-abcdef")
    }
}
