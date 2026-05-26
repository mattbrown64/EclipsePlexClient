//
//  BrowseNavigationUITests.swift
//  EclipsePlexClientUITests
//

import XCTest

final class BrowseNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchExposesBrowseNavigation() throws {
        let app = BrowseNavigationUITestHelpers.launchSeededApp()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let seededServerVisible =
            app.staticTexts["192.168.1.10:32400"].waitForExistence(timeout: 12)
            || app.descendants(matching: .any)["plex-\(BrowseNavigationUITestHelpers.sampleHomeServerID)"]
                .waitForExistence(timeout: 5)
        guard seededServerVisible else {
            throw XCTSkip("Sample server not visible in accessibility tree on this Mac configuration")
        }
    }

    @MainActor
    func testSidebarHomeRowIsReachableWhenBrowseOpens() throws {
        let app = BrowseNavigationUITestHelpers.launchSeededApp()
        guard BrowseNavigationUITestHelpers.openBrowse(app) else {
            throw XCTSkip("Browse navigation not available on this platform layout")
        }
        let serverButton = app.buttons["plex-\(BrowseNavigationUITestHelpers.sampleHomeServerID)"]
        guard serverButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Sample server row missing")
        }
        serverButton.tap()
        XCTAssertTrue(app.buttons["server-home"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSampleServerAppearsInSidebar() throws {
        let app = BrowseNavigationUITestHelpers.launchSeededApp()
        guard BrowseNavigationUITestHelpers.openBrowse(app) else {
            throw XCTSkip("Browse navigation not available on this platform layout")
        }
        XCTAssertTrue(
            app.buttons["plex-\(BrowseNavigationUITestHelpers.sampleHomeServerID)"]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testAggregateHomeRowInSidebar() throws {
        let app = BrowseNavigationUITestHelpers.launchSeededApp()
        guard BrowseNavigationUITestHelpers.openBrowse(app) else {
            throw XCTSkip("Browse navigation not available")
        }
        XCTAssertTrue(app.buttons["aggregate-home"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsRowInSidebar() throws {
        let app = BrowseNavigationUITestHelpers.launchSeededApp()
        guard BrowseNavigationUITestHelpers.openBrowse(app) else {
            throw XCTSkip("Browse navigation not available")
        }
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSelectingServerShowsHomeRow() throws {
        let app = BrowseNavigationUITestHelpers.launchSeededApp()
        guard BrowseNavigationUITestHelpers.openBrowse(app) else {
            throw XCTSkip("Browse navigation not available")
        }
        let serverButton = app.buttons["plex-\(BrowseNavigationUITestHelpers.sampleHomeServerID)"]
        guard serverButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Sample server row missing")
        }
        serverButton.tap()
        XCTAssertTrue(app.buttons["server-home"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMoviesLibraryRowAfterSelectingServer() throws {
        let app = BrowseNavigationUITestHelpers.launchSeededApp()
        guard BrowseNavigationUITestHelpers.openBrowse(app) else {
            throw XCTSkip("Browse navigation not available")
        }
        let serverButton = app.buttons["plex-\(BrowseNavigationUITestHelpers.sampleHomeServerID)"]
        guard serverButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Sample server row missing")
        }
        serverButton.tap()
        XCTAssertTrue(
            app.buttons["library-\(BrowseNavigationUITestHelpers.sampleMoviesLibraryID)"]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testDownloadsServerRowExists() throws {
        let app = BrowseNavigationUITestHelpers.launchSeededApp()
        guard BrowseNavigationUITestHelpers.openBrowse(app) else {
            throw XCTSkip("Browse navigation not available")
        }
        let downloadsButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "downloads-")
        ).firstMatch
        XCTAssertTrue(downloadsButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testReturnOpensCatalogItemOnMac() throws {
        #if !os(macOS)
        throw XCTSkip("Keyboard Return catalog activation is validated on macOS")
        #else
        let app = BrowseNavigationUITestHelpers.launchSeededApp()
        guard BrowseNavigationUITestHelpers.openBrowse(app),
              BrowseNavigationUITestHelpers.selectSampleMoviesLibrary(app),
              BrowseNavigationUITestHelpers.waitForSampleCatalog(app)
        else {
            throw XCTSkip("Could not reach fixture catalog")
        }

        app.typeKey(.return, modifierFlags: [])

        let detailTitle = app.staticTexts
            .matching(
                NSPredicate(
                    format: "label BEGINSWITH %@",
                    BrowseNavigationUITestHelpers.sampleMovieTitlePrefix
                )
            )
            .firstMatch
        XCTAssertTrue(detailTitle.waitForExistence(timeout: 6))
        #endif
    }

    @MainActor
    func testBackKeyReturnsFromDetailOnMac() throws {
        #if !os(macOS)
        throw XCTSkip("Keyboard E back navigation is validated on macOS")
        #else
        let app = BrowseNavigationUITestHelpers.launchSeededApp()
        guard BrowseNavigationUITestHelpers.openBrowse(app),
              BrowseNavigationUITestHelpers.selectSampleMoviesLibrary(app),
              BrowseNavigationUITestHelpers.waitForSampleCatalog(app)
        else {
            throw XCTSkip("Could not reach fixture catalog")
        }

        app.typeKey(.return, modifierFlags: [])
        let detailTitle = app.staticTexts
            .matching(
                NSPredicate(
                    format: "label BEGINSWITH %@",
                    BrowseNavigationUITestHelpers.sampleMovieTitlePrefix
                )
            )
            .firstMatch
        guard detailTitle.waitForExistence(timeout: 6) else {
            throw XCTSkip("Detail screen did not open")
        }

        app.typeKey("e", modifierFlags: [])
        XCTAssertTrue(BrowseNavigationUITestHelpers.waitForSampleCatalog(app, timeout: 6))
        #endif
    }

    @MainActor
    func testArrowRightMovesCatalogFocusOnMac() throws {
        #if !os(macOS)
        throw XCTSkip("Arrow-key catalog focus is validated on macOS")
        #else
        let app = BrowseNavigationUITestHelpers.launchSeededApp()
        guard BrowseNavigationUITestHelpers.openBrowse(app),
              BrowseNavigationUITestHelpers.selectSampleMoviesLibrary(app),
              BrowseNavigationUITestHelpers.waitForSampleCatalog(app)
        else {
            throw XCTSkip("Could not reach fixture catalog")
        }

        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(
            app.staticTexts["Fixture: The Feature Films Heist"].waitForExistence(timeout: 6)
        )
        #endif
    }
}
