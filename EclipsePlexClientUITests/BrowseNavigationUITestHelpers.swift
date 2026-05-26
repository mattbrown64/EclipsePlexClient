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
