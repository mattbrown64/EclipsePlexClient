import Foundation

enum PlaybackErrorMessages {
    /// User-facing message from VLC/libvlc or Plex resolver errors.
    static func friendly(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("http 401") || (lower.contains("401") && lower.contains("http")) {
            return "Plex rejected the sign-in token. Remove and re-add the server, or sign in again."
        }
        if lower.contains("http 403") {
            return "Plex denied access to this stream. Check that your account can play this item on the server."
        }
        if lower.contains("http 404") {
            return "Plex could not find this file. It may be offline on the server or the library needs a refresh."
        }
        if lower.contains("http 400") {
            return "Plex rejected the playback request. Try again or use the official Plex app to confirm the item plays."
        }
        if lower.contains("can't be opened") || lower.contains("unable to open") {
            return "VLC could not open the stream. The server may not support this format from external players."
        }
        if lower.contains("timed out") || lower.contains("timeout") {
            return "The connection timed out. Check your network or try again."
        }
        if lower.contains("server not configured") {
            return raw
        }
        return raw
    }
}
