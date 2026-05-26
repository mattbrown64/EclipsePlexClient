//
//  PlexSessionsXMLParserTests.swift
//  EclipsePlexClientTests
//

import Testing
@testable import EclipsePlexClient

struct PlexSessionsXMLParserTests {
    @Test func parsesVideoSessionAttributes() {
        let xml = """
        <MediaContainer size="1">
          <Video title="Inception" grandparentTitle="" parentTitle="" viewOffset="60000" duration="8880000"
            user="Matt" player="Plex for iOS" state="playing" sessionKey="sess-1" />
        </MediaContainer>
        """
        let sessions = PlexSessionsXMLParser.parse(xml)
        #expect(sessions.count == 1)
        #expect(sessions[0].title == "Inception")
        #expect(sessions[0].userName == "Matt")
        #expect(sessions[0].player == "Plex for iOS")
        #expect(sessions[0].state == "playing")
        #expect(sessions[0].viewOffsetMs == 60_000)
        #expect(sessions[0].durationMs == 8_880_000)
        #expect(sessions[0].terminateSessionId == "sess-1")
    }

    @Test func prefersNestedSessionIdForTerminate() {
        let xml = """
        <MediaContainer size="1">
          <Video title="Show" sessionKey="legacy-key">
            <Session id="real-session-id" />
          </Video>
        </MediaContainer>
        """
        let sessions = PlexSessionsXMLParser.parse(xml)
        #expect(sessions.count == 1)
        #expect(sessions[0].terminateSessionId == "real-session-id")
        #expect(sessions[0].id == "legacy-key")
    }

    @Test func parsesShowEpisodeSubtitle() {
        let xml = """
        <MediaContainer size="1">
          <Video title="Pilot" grandparentTitle="Breaking Bad" parentTitle="Season 1"
            user="Guest" player="Apple TV" state="paused" sessionKey="sess-2" />
        </MediaContainer>
        """
        let sessions = PlexSessionsXMLParser.parse(xml)
        #expect(sessions.count == 1)
        #expect(sessions[0].subtitle?.contains("Breaking Bad") == true)
    }
}
