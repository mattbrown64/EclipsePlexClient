//
//  OfflineDownloadFileValidatorTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct OfflineDownloadFileValidatorTests {
    @Test func rejectsTinyFile() throws {
        let url = try writeTempFile(bytes: [0x00, 0x01, 0x02])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: OfflineDownloadFileValidator.ValidationError.self) {
            try OfflineDownloadFileValidator.validate(at: url)
        }
    }

    @Test func acceptsMatroskaHeader() throws {
        var bytes = [UInt8](repeating: 0, count: 600 * 1024)
        bytes[0] = 0x1A
        bytes[1] = 0x45
        bytes[2] = 0xDF
        bytes[3] = 0xA3
        let url = try writeTempFile(bytes: bytes)
        defer { try? FileManager.default.removeItem(at: url) }
        try OfflineDownloadFileValidator.validate(at: url)
    }

    @Test func acceptsMP4FtypHeader() throws {
        var bytes = [UInt8](repeating: 0, count: 600 * 1024)
        bytes[4] = 0x66 // f
        bytes[5] = 0x74 // t
        bytes[6] = 0x79 // y
        bytes[7] = 0x70 // p
        let url = try writeTempFile(bytes: bytes)
        defer { try? FileManager.default.removeItem(at: url) }
        try OfflineDownloadFileValidator.validate(at: url)
    }

    @Test func rejectsPlainTextPayload() throws {
        var bytes = [UInt8](repeating: 0x41, count: 600 * 1024)
        let url = try writeTempFile(bytes: bytes)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: OfflineDownloadFileValidator.ValidationError.self) {
            try OfflineDownloadFileValidator.validate(at: url)
        }
    }

    private func writeTempFile(bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eclipseplex-test-\(UUID().uuidString).bin")
        try Data(bytes).write(to: url)
        return url
    }
}
