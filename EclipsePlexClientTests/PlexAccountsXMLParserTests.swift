//  PlexAccountsXMLParserTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct PlexAccountsXMLParserTests {
    @Test func parsesHomeUsers() {
        let xml = """
        <MediaContainer size="2">
          <User id="1" title="Owner" admin="1" thumb="/library/metadata/1/thumb" />
          <User id="2" title="Kid" restricted="1" />
        </MediaContainer>
        """
        let users = PlexAccountsXMLParser.parse(xml)
        #expect(users.count == 2)
        #expect(users[0].title == "Owner")
        #expect(users[0].isAdmin == true)
        #expect(users[0].isManaged == false)
        #expect(users[1].title == "Kid")
        #expect(users[1].isManaged == true)
    }
}
