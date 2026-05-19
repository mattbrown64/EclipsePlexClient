//
//  PlexServer+Playback.swift
//  EclipsePlexClient
//

import Foundation

extension PlexServer {

    /// Headers matching `PlexMediaServerClient.makeRequest` (safe for URLSession preflight).
    nonisolated var plexAPIHeaderFields: [String: String] {
        var fields: [String: String] = [
            "X-Plex-Client-Identifier": PlexHTTPConstants.clientIdentifier,
            "X-Plex-Product": PlexHTTPConstants.productName,
            "X-Plex-Product-Version": PlexHTTPConstants.productVersion,
        ]
        if let token = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            fields["X-Plex-Token"] = token
        }
        return fields
    }

    /// Headers for VLC (`http-extra-headers` on every segment request).
    nonisolated var vlcHTTPHeaderFields: [String: String] {
        var fields = plexAPIHeaderFields
        fields["X-Plex-Platform"] = "macOS"
        fields["X-Plex-Device"] = "EclipsePlexClient"
        fields["X-Plex-Client-Profile-Name"] = "Chrome"
        return fields
    }

    /// VLC/libvlc `http-extra-headers` value built from `vlcHTTPHeaderFields`.
    nonisolated var vlcHTTPExtraHeadersOption: String? {
        let lines = vlcHTTPHeaderFields
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\r\n")
        guard !lines.isEmpty else { return nil }
        return lines + "\r\n"
    }

    nonisolated var plexClientCapabilitiesHeader: String {
        "protocols=http-live-streaming,http-mp4-streaming,http-streaming-video,http-streaming-video-720p,http-mp4-video,http-mp4-video-720p;videoDecoders=h264{profile:high&resolution:2160&level:51};audioDecoders=aac,mp3,ac3"
    }

    /// Minimal transcode query (PlexConnect-style). Token is added by `makeRequest`; client fields go in VLC headers.
    nonisolated func plexTranscodeQueryItems(
        sessionID: String,
        metadataPath: String,
        mediaIndex: Int,
        partIndex: Int,
        protocol transcodeProtocol: String,
        directPlay: String,
        directStream: String
    ) -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "path", value: metadataPath),
            URLQueryItem(name: "mediaIndex", value: String(mediaIndex)),
            URLQueryItem(name: "partIndex", value: String(partIndex)),
            URLQueryItem(name: "protocol", value: transcodeProtocol),
            URLQueryItem(name: "session", value: sessionID),
            URLQueryItem(name: "location", value: "lan"),
            URLQueryItem(name: "fastSeek", value: "1"),
            URLQueryItem(name: "directPlay", value: directPlay),
            URLQueryItem(name: "directStream", value: directStream),
            URLQueryItem(name: "mediaBufferSize", value: "102400"),
            URLQueryItem(name: "videoResolution", value: "1280x720"),
            URLQueryItem(name: "videoQuality", value: "80"),
            URLQueryItem(name: "maxVideoBitrate", value: "8000"),
            URLQueryItem(name: "audioBoost", value: "100"),
            URLQueryItem(name: "subtitles", value: "none"),
        ]
        if transcodeProtocol == "http" {
            items.append(URLQueryItem(name: "copyts", value: "1"))
        }
        return items
    }
}
