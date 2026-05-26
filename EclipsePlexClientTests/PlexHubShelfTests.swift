import Foundation
import Testing
@testable import EclipsePlexClient

struct PlexHubShelfTests {
    @Test func hubDTOListDecodesSingleHub() throws {
        let json = """
        {
          "MediaContainer": {
            "Hub": {
              "title": "Recently Added",
              "hubKey": "home.recent",
              "Metadata": [
                { "ratingKey": "1", "title": "Test Movie", "type": "movie", "year": 2020 }
              ]
            }
          }
        }
        """.data(using: .utf8)!
        let root = try JSONDecoder().decode(PlexHubsRoot.self, from: json)
        #expect(root.MediaContainer.hubDTOs.count == 1)
        #expect(root.MediaContainer.hubDTOs[0].title == "Recently Added")
        #expect(root.MediaContainer.hubDTOs[0].records.count == 1)
    }

    @Test func libraryRootTabLabels() {
        #expect(LibraryRootTab.recommended.label == "Recommended")
        #expect(LibraryRootTab.browse.label == "Browse")
        #expect(LibraryBrowsePreferences.showsCollectionsTab(sectionType: .movie))
        #expect(!LibraryBrowsePreferences.showsCollectionsTab(sectionType: .photo))
    }
}
