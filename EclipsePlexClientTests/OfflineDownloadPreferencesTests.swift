//
//  OfflineDownloadPreferencesTests.swift
//  EclipsePlexClientTests
//

import Testing
@testable import EclipsePlexClient

struct OfflineDownloadPreferencesTests {
    @Test func defaultQualityIs720p() {
        let previous = OfflineDownloadPreferences.defaultQuality
        OfflineDownloadPreferences.defaultQuality = .p1080
        #expect(OfflineDownloadPreferences.defaultQuality == .p1080)
        OfflineDownloadPreferences.defaultQuality = previous
    }

    @Test func storageCapBytesScales() {
        let previous = OfflineDownloadPreferences.storageCapGB
        OfflineDownloadPreferences.storageCapGB = 10
        #expect(OfflineDownloadPreferences.storageCapBytes == 10 * 1_024 * 1_024 * 1_024)
        OfflineDownloadPreferences.storageCapGB = previous
    }
}
