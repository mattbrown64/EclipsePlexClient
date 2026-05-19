import Foundation

/// Returns a URL that VLCKit can open reliably under App Sandbox on macOS.
enum LocalMediaURL {
    static func forPlayback(_ url: URL) throws -> URL {
        guard url.isFileURL else { return url }

        #if os(macOS)
        // Sandboxed VLCKit often hangs on `opening` for files inside the .app bundle; play from tmp.
        if url.path.contains(".app/") {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent, isDirectory: false)
            let manager = FileManager.default
            if manager.fileExists(atPath: destination.path) {
                try manager.removeItem(at: destination)
            }
            try manager.copyItem(at: url, to: destination)
            return destination
        }
        #endif

        return url
    }
}
