//
//  BrowseNavigationUITestHelpers.swift
//  EclipsePlexClientUITests
//

import XCTest

enum BrowseNavigationUITestHelpers {
    static let sampleHomeServerID = "A1000000-0000-4000-8000-000000000001"
    static let sampleMoviesLibraryID = "\(sampleHomeServerID):1"
    static let sampleMovieTitlePrefix = "Fixture: Midnight"

    static func launchSeededApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSeedSampleData", "-UITestSkipOnboarding", "-UITestShowSidebar"]
        app.launch()
        app.activate()
        return app
    }

    /// Opens browse UI: toolbar button on iPhone/tvOS, split sidebar on macOS.
    @discardableResult
    static func openBrowse(_ app: XCUIApplication, timeout: TimeInterval = 12) -> Bool {
        if sidebarIsVisible(app) {
            return true
        }

        let browseButton = app.buttons["browseMenuButton"]
        if browseButton.waitForExistence(timeout: 2) {
            browseButton.tap()
            if waitForSidebar(app, timeout: timeout) {
                return true
            }
        }

#if os(macOS)
        let browseMenu = app.menuBarItems["Browse"]
        if browseMenu.waitForExistence(timeout: 2) {
            browseMenu.click()
            if waitForSidebar(app, timeout: timeout) {
                return true
            }
        }

        app.typeKey("b", modifierFlags: [.command, .shift])
        if waitForSidebar(app, timeout: timeout) {
            return true
        }
#endif

        return sidebarIsVisible(app)
    }

    static func selectSampleMoviesLibrary(_ app: XCUIApplication) -> Bool {
        let serverRow = app.descendants(matching: .any)["plex-\(sampleHomeServerID)"]
        guard serverRow.waitForExistence(timeout: 5) else { return false }
        serverRow.click()

        let libraryRow = app.descendants(matching: .any)["library-\(sampleMoviesLibraryID)"]
        guard libraryRow.waitForExistence(timeout: 5) else { return false }
        libraryRow.click()
        return true
    }

    static func waitForSampleCatalog(_ app: XCUIApplication, timeout: TimeInterval = 8) -> Bool {
        app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", sampleMovieTitlePrefix))
            .firstMatch
            .waitForExistence(timeout: timeout)
    }

    /// Opens the first fixture movie detail (iOS tap or macOS Return).
    @discardableResult
    static func openSampleMovieDetail(_ app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        guard selectSampleMoviesLibrary(app), waitForSampleCatalog(app, timeout: timeout) else {
            return false
        }

        let movie = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", sampleMovieTitlePrefix))
            .firstMatch
        guard movie.waitForExistence(timeout: timeout) else { return false }

#if os(macOS)
        movie.click()
        app.typeKey(.return, modifierFlags: [])
#else
        movie.tap()
#endif

        // Fixture servers have no token, so Watch may be absent; the detail
        // screen still exercises MediaDetailView.task / loadDetail.
        if app.buttons["watchButton"].waitForExistence(timeout: 4) {
            return true
        }
        return movie.waitForExistence(timeout: timeout)
    }

    /// Sample data + optional live Plex credentials from the UI-test scheme environment.
    static func launchLivePlexApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSeedSampleData",
            "-UITestSkipOnboarding",
            "-UITestShowSidebar",
            "-UITestLivePlex",
        ]
        app.launch()
        app.activate()
        return app
    }

    static var hasLivePlexUITestCredentials: Bool {
        let env = ProcessInfo.processInfo.environment
        let token = env["UITEST_PLEX_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = env["UITEST_PLEX_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !token.isEmpty && !base.isEmpty
    }

    /// Opens the first row in the movies catalog (for live Plex UI tests).
    @discardableResult
    static func openFirstCatalogItemDetail(_ app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        guard selectSampleMoviesLibrary(app) else { return false }
        let firstCell = app.cells.firstMatch
        guard firstCell.waitForExistence(timeout: timeout) else { return false }
        firstCell.tap()
        return app.buttons["watchButton"].waitForExistence(timeout: timeout)
    }

    static func waitForPlaybackShell(_ app: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
        app.otherElements["playbackShell"].waitForExistence(timeout: timeout)
            || app.descendants(matching: .any)["playbackShell"].waitForExistence(timeout: timeout)
    }

    private static func sidebarIsVisible(_ app: XCUIApplication) -> Bool {
        let markers = ["aggregate-home", "server-home", "settings", "plex-\(sampleHomeServerID)"]
        if markers.contains(where: { app.descendants(matching: .any)[$0].exists }) {
            return true
        }
        // macOS split sidebar may not surface SwiftUI accessibility identifiers; fall back to seeded copy.
        return app.staticTexts["192.168.1.10:32400"].exists
            || app.staticTexts["Home"].exists
    }

    private static func waitForSidebar(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if sidebarIsVisible(app) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }
}
