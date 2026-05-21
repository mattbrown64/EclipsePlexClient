//
//  OfflineDownloadProgressFormatter.swift
//  EclipsePlexClient
//

import Foundation

enum OfflineDownloadProgressFormatter {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "—" }
        return "\(bytes(Int64(bytesPerSecond.rounded())))/s"
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    static func progressLine(
        progress: Double,
        bytesWritten: Int64,
        expectedBytes: Int64?,
        speedBytesPerSecond: Double?
    ) -> String {
        var parts: [String] = [percent(progress)]
        if let speedBytesPerSecond, speedBytesPerSecond > 0 {
            parts.append(speed(speedBytesPerSecond))
        }
        if let expectedBytes, expectedBytes > 0 {
            parts.append("\(bytes(bytesWritten)) / \(bytes(expectedBytes))")
        } else if bytesWritten > 0 {
            parts.append(bytes(bytesWritten))
        }
        return parts.joined(separator: " · ")
    }
}
