import Foundation

/// Returns a URL that VLCKit can open reliably under App Sandbox.
enum LocalMediaURL {
    static func forPlayback(_ url: URL) throws -> URL {
        let fileURL = url.isFileURL ? url : URL(fileURLWithPath: url.path)
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else {
            throw NSError(
                domain: "LocalMediaURL",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Offline file not found at \(fileURL.path)",
                ]
            )
        }

        #if os(macOS)
        // Sandboxed VLCKit often hangs on `opening` for files inside the .app bundle; play from tmp.
        if fileURL.path.contains(".app/") {
            return try copyToTemporaryPlaybackCopy(source: fileURL, manager: manager)
        }
        #endif

        return fileURL.standardizedFileURL
    }

    private static func copyToTemporaryPlaybackCopy(
        source: URL,
        manager: FileManager
    ) throws -> URL {
        let destination = manager.temporaryDirectory
            .appendingPathComponent("eclipseplex-play-\(UUID().uuidString)-\(source.lastPathComponent)", isDirectory: false)
        if manager.fileExists(atPath: destination.path) {
            try manager.removeItem(at: destination)
        }
        try manager.copyItem(at: source, to: destination)
        return destination
    }
}
