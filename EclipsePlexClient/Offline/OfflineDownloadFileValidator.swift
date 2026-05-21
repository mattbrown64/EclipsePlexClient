//
//  OfflineDownloadFileValidator.swift
//  EclipsePlexClient
//

import Foundation

enum OfflineDownloadFileValidator {
    /// Reject empty Plex error pages and truncated transcode stubs.
    static let minimumBytes: Int64 = 512 * 1024

    static func validate(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw ValidationError.notAFile
        }
        let size = Int64(values.fileSize ?? 0)
        guard size >= minimumBytes else {
            throw ValidationError.tooSmall(bytes: size)
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 64) ?? Data()
        guard looksLikeMedia(prefix) else {
            throw ValidationError.unrecognizedFormat
        }
    }

    private static func looksLikeMedia(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let bytes = [UInt8](data.prefix(12))
        // Matroska EBML
        if bytes.count >= 4, bytes[0] == 0x1A, bytes[1] == 0x45, bytes[2] == 0xDF, bytes[3] == 0xA3 {
            return true
        }
        // ISO BMFF (mp4/m4v/mov)
        if data.count >= 8 {
            let box = String(bytes: bytes[4..<8], encoding: .ascii)
            if box == "ftyp" || box == "moov" || box == "mdat" {
                return true
            }
        }
        // MPEG-TS
        if bytes[0] == 0x47 {
            return true
        }
        // AVI RIFF
        if bytes.count >= 4,
           bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46 {
            return true
        }
        return false
    }

    enum ValidationError: LocalizedError {
        case notAFile
        case tooSmall(bytes: Int64)
        case unrecognizedFormat

        var errorDescription: String? {
            switch self {
            case .notAFile:
                return "The download is not a valid video file."
            case .tooSmall(let bytes):
                return "The download is too small (\(bytes) bytes). Plex may have returned an error instead of the video file."
            case .unrecognizedFormat:
                return "The downloaded file does not look like a playable video."
            }
        }
    }
}
