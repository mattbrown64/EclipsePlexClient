//
//  OfflineDownloadFileValidatorExtendedTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct OfflineDownloadFileValidatorExtendedTests {
    @Test func acceptsMPEGTSHeader() throws {
        var bytes = [UInt8](repeating: 0, count: 600 * 1024)
        bytes[0] = 0x47
        let url = try writeTempFile(bytes: bytes)
        defer { try? FileManager.default.removeItem(at: url) }
        try OfflineDownloadFileValidator.validate(at: url)
    }

    @Test func acceptsAVIRIFFHeader() throws {
        var bytes = [UInt8](repeating: 0, count: 600 * 1024)
        bytes[0] = 0x52
        bytes[1] = 0x49
        bytes[2] = 0x46
        bytes[3] = 0x46
        bytes[8] = 0x41
        bytes[9] = 0x56
        bytes[10] = 0x49
        bytes[11] = 0x20
        let url = try writeTempFile(bytes: bytes)
        defer { try? FileManager.default.removeItem(at: url) }
        try OfflineDownloadFileValidator.validate(at: url)
    }

    @Test func minimumBytesIs512KB() {
        #expect(OfflineDownloadFileValidator.minimumBytes == 512 * 1024)
    }

    private func writeTempFile(bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eclipseplex-test-\(UUID().uuidString).bin")
        try Data(bytes).write(to: url)
        return url
    }
}
