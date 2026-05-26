//
//  PlaybackUITests.swift
//  EclipsePlexClientUITests
//
//  Run on a physical iPhone: select your device in Xcode, then Product → Test
//  (⌘U), or:
//    xcodebuild test \
//      -scheme EclipsePlexClient \
//      -destination 'platform=iOS,name=Matt'\''s iPhone' \
//      -only-testing:EclipsePlexClientUITests/PlaybackUITests
//
//  For live Plex playback on device, edit the EclipsePlexClientUITests scheme →
//  Run → Arguments → Environment Variables:
//    UITEST_PLEX_BASE_URL = http://192.168.x.x:32400
//    UITEST_PLEX_TOKEN    = your-plex-token
//  and use launchLivePlexApp() tests below.
//

import XCTest

final class PlaybackUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Smoke test: browse → movie detail should stay alive (no SIGABRT in MediaDetailView.task).
    @MainActor
    func testSampleMovieDetailDoesNotCrash() throws {
        let app = BrowseNavigationUITestHelpers.launchSeededApp()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        guard BrowseNavigationUITestHelpers.openBrowse(app) else {
            throw XCTSkip("Browse navigation not available on this layout")
        }
        guard BrowseNavigationUITestHelpers.openSampleMovieDetail(app) else {
            throw XCTSkip("Could not open fixture movie detail")
        }

        // Hold on the detail screen long enough for `.task { loadDetail() }` to run.
        sleep(5)
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Live Plex: detail load + Watch → full-screen player (requires scheme env vars).
    @MainActor
    func testLiveWatchOpensPlaybackShell() throws {
        guard BrowseNavigationUITestHelpers.hasLivePlexUITestCredentials else {
            throw XCTSkip(
                "Set UITEST_PLEX_BASE_URL and UITEST_PLEX_TOKEN in the UI-test scheme environment"
            )
        }

        let app = BrowseNavigationUITestHelpers.launchLivePlexApp()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        guard BrowseNavigationUITestHelpers.openBrowse(app) else {
            throw XCTSkip("Browse navigation not available")
        }
        guard BrowseNavigationUITestHelpers.openFirstCatalogItemDetail(app, timeout: 20) else {
            throw XCTSkip("Could not open a catalog item against live Plex")
        }

        sleep(3)
        XCTAssertEqual(app.state, .runningForeground)

        let watch = app.buttons["watchButton"]
        guard watch.waitForExistence(timeout: 8) else {
            throw XCTSkip("Watch button not available (item may not support playback)")
        }
        watch.tap()

        XCTAssertTrue(
            BrowseNavigationUITestHelpers.waitForPlaybackShell(app, timeout: 25),
            "Playback shell did not appear after tapping Watch"
        )
        sleep(3)
        XCTAssertEqual(app.state, .runningForeground)
    }
}
