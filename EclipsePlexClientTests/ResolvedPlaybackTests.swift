import Foundation
import Testing
@testable import EclipsePlexClient

struct ResolvedPlaybackTests {
    @Test func streamSignatureChangesWithOptions() {
        let url = URL(string: "https://example.com/video.mkv")!
        let a = ResolvedPlayback(
            candidates: [PlaybackStreamCandidate(url: url, streamKind: .plexDirect, label: "A")],
            streamOptions: PlaybackStreamOptions(videoResolution: .original, subtitleSelection: .off)
        )
        let b = ResolvedPlayback(
            candidates: [PlaybackStreamCandidate(url: url, streamKind: .plexDirect, label: "B")],
            streamOptions: PlaybackStreamOptions(videoResolution: .p720, subtitleSelection: .auto)
        )
        #expect(a.streamSignature != b.streamSignature)
    }
}
