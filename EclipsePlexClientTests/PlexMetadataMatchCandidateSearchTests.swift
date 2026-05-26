//
//  PlexMetadataMatchCandidateSearchTests.swift
//  EclipsePlexClientTests
//

import Testing
@testable import EclipsePlexClient

struct PlexMetadataMatchCandidateSearchTests {
    @Test func matchesSearchByTitleAndYear() {
        let candidate = PlexMetadataMatchCandidate(
            guid: "guid-1",
            title: "Fight Club",
            year: 1999,
            summary: "An insomniac office worker",
            thumbPath: nil
        )
        #expect(candidate.matchesSearch(trimmedQuery: "fight"))
        #expect(candidate.matchesSearch(trimmedQuery: "1999"))
        #expect(candidate.matchesSearch(trimmedQuery: "insomniac"))
        #expect(!candidate.matchesSearch(trimmedQuery: "matrix"))
    }
}
