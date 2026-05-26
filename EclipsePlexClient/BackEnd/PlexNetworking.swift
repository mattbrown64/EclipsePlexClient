//
//  PlexNetworking.swift
//  EclipsePlexClient
//
//  Process-wide tuned URLSession + shared JSONDecoder for Plex traffic. Keeps
//  background download sessions separate (`OfflineDownloadBackgroundSession`).
//

import Foundation

enum PlexNetworking {
    /// Tuned `URLSession` used by `PlexMediaServerClient`, `PlexAccountAPI`, and
    /// artwork fetches. Pools connections per host so scrolling a poster grid
    /// reuses the same TCP/TLS session as catalog requests.
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90
        config.waitsForConnectivity = true
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            diskPath: "PlexHTTPCache"
        )
        config.httpShouldUsePipelining = true
        return URLSession(configuration: config)
    }()

    /// Decoder reuse avoids per-response allocation on hot paths (hubs, paged catalog).
    static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()
}
