//
//  AppSignposts.swift
//  EclipsePlexClient
//
//  Lightweight `OSSignposter` wrappers for Instruments. Names line up with the
//  hot paths called out in the perf audit so traces can attribute time directly
//  to artwork decode, Plex JSON fetches, playback resolution, and VLC ticks.
//

import Foundation
import OSLog

enum AppSignposts {
    static let log = OSLog(subsystem: subsystem, category: "Performance")
    static let signposter = OSSignposter(subsystem: subsystem, category: "Performance")

    private static var subsystem: String { Bundle.main.bundleIdentifier ?? "EclipsePlexClient" }

    static func interval<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try work()
    }

    static func interval<T>(_ name: StaticString, _ work: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try await work()
    }

    static func event(_ name: StaticString, _ message: String? = nil) {
        if let message {
            signposter.emitEvent(name, "\(message, privacy: .public)")
        } else {
            signposter.emitEvent(name)
        }
    }
}
