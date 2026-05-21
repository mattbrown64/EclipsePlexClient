import Foundation

#if os(macOS)
import VLCKit
#elseif os(tvOS)
import TVVLCKit
#elseif canImport(MobileVLCKit)
import MobileVLCKit
#endif

/// HTTP options shared by macOS and iOS VLC playback for remote Plex streams.
enum VLCNetworkMediaOptions {
    static func apply(to media: VLCMedia, url: URL, headerFields: [String: String]) {
        guard !url.isFileURL else { return }
        media.addOption(":http-user-agent=\(PlexHTTPConstants.productName)/\(PlexHTTPConstants.productVersion)")
        media.addOption(":http-reconnect")
        media.addOption(":network-caching=5000")
        guard !headerFields.isEmpty else { return }
        let lines = headerFields
            .map { key, value in
                let escaped = value
                    .replacingOccurrences(of: "\r", with: "")
                    .replacingOccurrences(of: "\n", with: "")
                return "\(key): \(escaped)"
            }
            .joined(separator: "\r\n")
        media.addOption(":http-extra-headers=\(lines)\r\n")
    }
}
