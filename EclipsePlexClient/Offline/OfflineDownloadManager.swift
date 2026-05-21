//
//  OfflineDownloadManager.swift
//  EclipsePlexClient
//

import Combine
import Foundation
import Network

/// Queues and performs offline Plex downloads; persists records and files on disk.
@MainActor
final class OfflineDownloadManager: ObservableObject {
    @Published private(set) var records: [OfflineDownloadRecord] = []
    @Published private(set) var catalogRevision = 0
    @Published private(set) var isOnWiFi = true
    /// Smoothed bytes/sec for the active transfer (UI only).
    @Published private(set) var transferSpeedByRecordID: [UUID: Double] = [:]

    private var activeDownloadID: UUID?
    private var activeDownloadSession: URLSession?
    private var activeDownloadDelegate: OfflineDownloadSessionDelegate?
    private var lastProgressLogAt: [UUID: Date] = [:]
    private var lastPersistAt: [UUID: Date] = [:]
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "OfflineDownloadManager.path")
    private var serverResolver: (() -> [PlexServer])?

    init() {
        records = OfflineDownloadStore.load()
        reconcileStaleDownloads()
        startPathMonitor()
    }

    deinit {
        pathMonitor?.cancel()
    }

    func configure(registry: PlexServerRegistry) {
        serverResolver = { registry.allServers }
        reconcileStaleDownloads()
        Task {
            await OfflineScrobbleQueue.flush(servers: registry.allServers)
            await backfillMissingThumbs()
            await pumpQueue()
        }
    }

    /// Fetches poster paths for legacy records saved without artwork metadata.
    func backfillMissingThumbs() async {
        let targets = records.filter { record in
            guard record.state != .cancelled else { return false }
            let missingEpisodeThumb = record.thumbPath == nil || record.thumbPath?.isEmpty == true
            let missingShowThumb = record.resolvedMediaKind == .episode
                && (record.showThumbPath == nil || record.showThumbPath?.isEmpty == true)
            return missingEpisodeThumb || missingShowThumb
        }
        guard !targets.isEmpty else { return }
        for record in targets {
            guard let server = server(for: record), server.usesLivePlexAPI else { continue }
            guard let client = try? PlexMediaServerClient(server: server),
                  let detail = try? await client.fetchMediaDetail(ratingKey: record.ratingKey)
            else { continue }
            updateRecord(id: record.id) { row in
                if row.thumbPath == nil || row.thumbPath?.isEmpty == true,
                   let thumb = detail.thumbPath, !thumb.isEmpty {
                    row.thumbPath = thumb
                }
                if case .episode(let episode) = detail.node {
                    if row.showThumbPath == nil || row.showThumbPath?.isEmpty == true,
                       let showThumb = episode.showThumbPath, !showThumb.isEmpty {
                        row.showThumbPath = showThumb
                    }
                    if let showKey = episode.showRatingKey, !showKey.isEmpty {
                        row.showRatingKey = showKey
                    }
                }
            }
        }
        persist()
    }

    // MARK: - Queries

    func record(serverId: UUID, ratingKey: String, quality: PlaybackVideoResolution) -> OfflineDownloadRecord? {
        records.first {
            $0.serverId == serverId && $0.ratingKey == ratingKey && $0.quality == quality
        }
    }

    func isDownloaded(serverId: UUID, ratingKey: String) -> Bool {
        records.contains { $0.serverId == serverId && $0.ratingKey == ratingKey && $0.isPlayable }
    }

    func playableRecord(serverId: UUID, ratingKey: String) -> OfflineDownloadRecord? {
        records.first { $0.serverId == serverId && $0.ratingKey == ratingKey && $0.isPlayable }
    }

    func record(id: UUID) -> OfflineDownloadRecord? {
        records.first { $0.id == id }
    }

    func record(forCatalogRatingKey ratingKey: String) -> OfflineDownloadRecord? {
        guard let id = OfflineDownloadCatalog.recordID(fromCatalogRatingKey: ratingKey) else { return nil }
        return record(id: id)
    }

    func localFileURL(for record: OfflineDownloadRecord) -> URL? {
        guard let relative = record.relativeFilePath else { return nil }
        let url = OfflineDownloadStore.downloadsDirectory.appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var totalDownloadedBytes: Int64 {
        records.compactMap { record -> Int64? in
            guard let url = localFileURL(for: record) else { return nil }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            return attrs?[.size] as? Int64
        }
        .reduce(0, +)
    }

    // MARK: - Enqueue

    func enqueue(
        server: PlexServer,
        ratingKey: String,
        title: String,
        thumbPath: String?,
        quality: PlaybackVideoResolution,
        mediaKind: OfflineDownloadRecord.MediaKind = .unknown,
        showTitle: String? = nil,
        showRatingKey: String? = nil,
        showThumbPath: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeTitle: String? = nil
    ) async {
        if let existing = record(serverId: server.id, ratingKey: ratingKey, quality: quality),
           existing.state == .pending || existing.state == .downloading {
            return
        }
        if let existing = playableRecord(serverId: server.id, ratingKey: ratingKey),
           existing.quality == quality {
            return
        }
        records.removeAll {
            $0.serverId == server.id && $0.ratingKey == ratingKey && $0.quality == quality
        }
        var resolvedKind = mediaKind
        var resolvedShowTitle = showTitle
        var resolvedShowRatingKey = showRatingKey
        var resolvedSeason = seasonNumber
        var resolvedEpisode = episodeNumber
        var resolvedEpisodeTitle = episodeTitle
        var resolvedThumb = thumbPath
        var resolvedShowThumb = showThumbPath
        let needsEpisodeArtwork = resolvedKind == .episode
            && ((resolvedShowThumb == nil || resolvedShowThumb?.isEmpty == true)
                || resolvedShowRatingKey == nil || resolvedShowRatingKey?.isEmpty == true)
        if resolvedKind == .unknown || needsEpisodeArtwork {
            let metadata = await fetchEnqueueMetadata(server: server, ratingKey: ratingKey, title: title)
            if resolvedKind == .unknown {
                resolvedKind = metadata.mediaKind
                resolvedShowTitle = resolvedShowTitle ?? metadata.showTitle
                resolvedShowRatingKey = resolvedShowRatingKey ?? metadata.showRatingKey
                resolvedSeason = resolvedSeason ?? metadata.seasonNumber
                resolvedEpisode = resolvedEpisode ?? metadata.episodeNumber
                resolvedEpisodeTitle = resolvedEpisodeTitle ?? metadata.episodeTitle
                resolvedThumb = resolvedThumb ?? metadata.thumbPath
            }
            if resolvedKind == .episode {
                resolvedShowRatingKey = resolvedShowRatingKey ?? metadata.showRatingKey
                resolvedShowThumb = resolvedShowThumb ?? metadata.showThumbPath
                if resolvedThumb == nil || resolvedThumb?.isEmpty == true {
                    resolvedThumb = metadata.thumbPath
                }
            }
        }
        records.append(
            OfflineDownloadRecord.new(
                server: server,
                ratingKey: ratingKey,
                title: title,
                thumbPath: resolvedThumb,
                showThumbPath: resolvedShowThumb,
                quality: quality,
                mediaKind: resolvedKind,
                showTitle: resolvedShowTitle,
                showRatingKey: resolvedShowRatingKey,
                seasonNumber: resolvedSeason,
                episodeNumber: resolvedEpisode,
                episodeTitle: resolvedEpisodeTitle
            )
        )
        persist()
        await pumpQueue()
    }

    func enqueueSeason(
        server: PlexServer,
        library: PlexLibrary,
        seasonRatingKey: String,
        quality: PlaybackVideoResolution
    ) async throws {
        let client = try PlexMediaServerClient(server: server)
        let nodes = try await client.catalogNodes(
            library: library,
            parent: .season(ratingKey: seasonRatingKey),
            watchFilter: .all
        )
        for node in nodes {
            guard case .episode(let episode) = node else { continue }
            await enqueue(
                server: server,
                ratingKey: episode.ratingKey,
                title: "\(episode.showTitle) · S\(episode.seasonNumber)E\(episode.episodeNumber)",
                thumbPath: episode.thumbPath,
                quality: quality,
                mediaKind: .episode,
                showTitle: episode.showTitle,
                showRatingKey: episode.showRatingKey,
                showThumbPath: episode.showThumbPath,
                seasonNumber: episode.seasonNumber,
                episodeNumber: episode.episodeNumber,
                episodeTitle: episode.title
            )
        }
    }

    func enqueueShow(
        server: PlexServer,
        library: PlexLibrary,
        showRatingKey: String,
        quality: PlaybackVideoResolution
    ) async throws {
        let client = try PlexMediaServerClient(server: server)
        let seasonNodes = try await client.catalogNodes(
            library: library,
            parent: .show(ratingKey: showRatingKey),
            watchFilter: .all
        )
        for node in seasonNodes {
            guard case .season(let season) = node else { continue }
            try await enqueueSeason(
                server: server,
                library: library,
                seasonRatingKey: season.ratingKey,
                quality: quality
            )
        }
    }

    func cancel(id: UUID) {
        if activeDownloadID == id {
            tearDownActiveDownloadSession()
            activeDownloadID = nil
        }
        transferSpeedByRecordID.removeValue(forKey: id)
        updateRecord(id: id) {
            $0.state = .cancelled
            $0.errorMessage = nil
        }
        persist()
        Task { await pumpQueue() }
    }

    /// Active downloads for sidebar badge (pending, downloading, or failed).
    var activeQueueCount: Int {
        records.filter { $0.state == .pending || $0.state == .downloading || $0.state == .failed }.count
    }

    /// Removes every download for a TV show group key.
    func deleteShow(groupKey: String) {
        let ids = records.filter { $0.showGroupKey == groupKey }.map(\.id)
        for id in ids {
            delete(id: id)
        }
    }

    func delete(id: UUID) {
        if let record = records.first(where: { $0.id == id }),
           let url = localFileURL(for: record) {
            try? FileManager.default.removeItem(at: url)
        }
        records.removeAll { $0.id == id }
        persist()
    }

    func server(for record: OfflineDownloadRecord) -> PlexServer? {
        servers().first { $0.id == record.serverId }
    }

    func transferSpeed(for recordID: UUID) -> Double? {
        transferSpeedByRecordID[recordID]
    }

    func pumpQueueIfAllowed() async {
        await pumpQueue()
    }

    func retry(id: UUID) {
        transferSpeedByRecordID.removeValue(forKey: id)
        updateRecord(id: id) {
            $0.state = .pending
            $0.progress = 0
            $0.bytesWritten = 0
            $0.errorMessage = nil
        }
        persist()
        Task { await pumpQueue() }
    }

    // MARK: - Queue

    private func pumpQueue() async {
        guard activeDownloadID == nil else { return }
        guard canStartDownload() else { return }
        guard let nextIndex = records.firstIndex(where: { $0.state == .pending }) else { return }

        let next = records[nextIndex]
        guard let server = servers().first(where: { $0.id == next.serverId }) else {
            fail(id: next.id, message: "Server not found.")
            await pumpQueue()
            return
        }

        activeDownloadID = next.id
        updateRecord(id: next.id) { $0.state = .downloading }
        persist()

        do {
            let client = try PlexMediaServerClient(server: server)
            let source = try await client.resolveDownloadSource(
                ratingKey: next.ratingKey,
                server: server,
                quality: next.quality
            )
            let relativePath = "media/\(next.serverId.uuidString)/\(source.suggestedFilename)"
            let destination = OfflineDownloadStore.downloadsDirectory.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            try await performDownload(source: source, to: destination, recordID: next.id)

            updateRecord(id: next.id) {
                $0.state = .completed
                $0.progress = 1
                $0.relativeFilePath = relativePath
                $0.completedAt = Date()
                $0.errorMessage = nil
            }
            persist()
            await enforceStorageCap()
        } catch {
            fail(id: next.id, message: error.localizedDescription)
        }

        activeDownloadID = nil
        await pumpQueue()
    }

    private func performDownload(
        source: PlexMediaServerClient.PlexDownloadSource,
        to destination: URL,
        recordID: UUID
    ) async throws {
        var request = URLRequest(url: source.url)
        request.timeoutInterval = 60 * 60
        for (key, value) in source.httpHeaderFields {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let title = records.first(where: { $0.id == recordID })?.title ?? recordID.uuidString
        updateRecord(id: recordID) { $0.progress = 0 }
        NSLog("[EclipsePlex] Download started: \"%@\"", title)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = OfflineDownloadSessionDelegate(
                recordID: recordID,
                recordTitle: title,
                destination: destination,
                manager: self,
                continuation: continuation
            )
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            activeDownloadDelegate = delegate
            activeDownloadSession = session
            let task = session.downloadTask(with: request)
            delegate.downloadTask = task
            task.resume()
        }
        tearDownActiveDownloadSession()
        transferSpeedByRecordID.removeValue(forKey: recordID)
        lastProgressLogAt.removeValue(forKey: recordID)
        lastPersistAt.removeValue(forKey: recordID)

        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
        updateRecord(id: recordID) {
            $0.bytesWritten = size
            $0.expectedBytes = size > 0 ? size : $0.expectedBytes
            $0.progress = 1
        }
        NSLog(
            "[EclipsePlex] Download finished: \"%@\" · %@",
            title,
            OfflineDownloadProgressFormatter.bytes(size)
        )
    }

    fileprivate func updateDownloadProgress(
        recordID: UUID,
        recordTitle: String,
        bytesWritten: Int64,
        expectedBytes: Int64?,
        speedBytesPerSecond: Double
    ) {
        let progress: Double
        if let expectedBytes, expectedBytes > 0 {
            progress = min(1, Double(bytesWritten) / Double(expectedBytes))
        } else {
            progress = min(0.99, max(0.02, Double(bytesWritten) / 2_000_000_000))
        }

        transferSpeedByRecordID[recordID] = speedBytesPerSecond
        updateRecord(id: recordID) {
            $0.bytesWritten = bytesWritten
            $0.progress = progress
            if let expectedBytes, expectedBytes > 0 {
                $0.expectedBytes = expectedBytes
            }
        }

        let now = Date()
        if now.timeIntervalSince(lastProgressLogAt[recordID] ?? .distantPast) >= 1 {
            lastProgressLogAt[recordID] = now
            NSLog(
                "[EclipsePlex] Download \"%@\": %@ · %@ · %@",
                recordTitle,
                OfflineDownloadProgressFormatter.percent(progress),
                OfflineDownloadProgressFormatter.speed(speedBytesPerSecond),
                OfflineDownloadProgressFormatter.progressLine(
                    progress: progress,
                    bytesWritten: bytesWritten,
                    expectedBytes: expectedBytes,
                    speedBytesPerSecond: nil
                )
            )
        }

        if now.timeIntervalSince(lastPersistAt[recordID] ?? .distantPast) >= 2 {
            lastPersistAt[recordID] = now
            persist()
        }
    }

    private func tearDownActiveDownloadSession() {
        activeDownloadSession?.finishTasksAndInvalidate()
        activeDownloadSession = nil
        activeDownloadDelegate = nil
    }

    /// Marks completed rows missing/invalid on disk as failed (e.g. after a bad transcode-URL download).
    private func reconcileStaleDownloads() {
        var changed = false
        for index in records.indices {
            guard records[index].state == .completed else { continue }
            guard let path = records[index].relativeFilePath else {
                records[index].state = .failed
                records[index].errorMessage = "Download file is missing."
                changed = true
                continue
            }
            let url = OfflineDownloadStore.downloadsDirectory.appendingPathComponent(path)
            do {
                try OfflineDownloadFileValidator.validate(at: url)
            } catch {
                records[index].state = .failed
                records[index].errorMessage = error.localizedDescription
                changed = true
            }
        }
        if changed {
            persist()
        }
    }

    private func fail(id: UUID, message: String) {
        let title = records.first(where: { $0.id == id })?.title ?? id.uuidString
        NSLog("[EclipsePlex] Download failed: \"%@\" — %@", title, message)
        transferSpeedByRecordID.removeValue(forKey: id)
        lastProgressLogAt.removeValue(forKey: id)
        lastPersistAt.removeValue(forKey: id)
        updateRecord(id: id) {
            $0.state = .failed
            $0.errorMessage = message
        }
        persist()
        activeDownloadID = nil
    }

    private func canStartDownload() -> Bool {
        if OfflineDownloadPreferences.wifiOnly {
            return isOnWiFi
        }
        return true
    }

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let onWiFi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isOnWiFi = onWiFi
                if self.canStartDownload() {
                    await self.pumpQueue()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    private func enforceStorageCap() async {
        var total = totalDownloadedBytes
        let cap = OfflineDownloadPreferences.storageCapBytes
        guard total > cap else { return }

        var completed = records.filter(\.isPlayable).sorted {
            ($0.completedAt ?? $0.createdAt) < ($1.completedAt ?? $1.createdAt)
        }

        if OfflineDownloadPreferences.pruneWatchedWhenOverCap {
            for server in servers() where server.usesLivePlexAPI {
                guard let client = try? PlexMediaServerClient(server: server) else { continue }
                for index in completed.indices.reversed() {
                    let record = completed[index]
                    guard record.serverId == server.id else { continue }
                    if let detail = try? await client.fetchMediaDetail(ratingKey: record.ratingKey),
                       detail.isWatched {
                        delete(id: record.id)
                        total = totalDownloadedBytes
                        completed.remove(at: index)
                        if total <= cap { return }
                    }
                }
            }
        }

        while total > cap, let oldest = completed.first {
            delete(id: oldest.id)
            completed.removeFirst()
            total = totalDownloadedBytes
        }
    }

    private func servers() -> [PlexServer] {
        serverResolver?() ?? []
    }

    private func persist() {
        OfflineDownloadStore.save(records)
        catalogRevision &+= 1
    }

    private func updateRecord(id: UUID, mutate: (inout OfflineDownloadRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        mutate(&records[index])
    }

    private struct EnqueueMetadata {
        var mediaKind: OfflineDownloadRecord.MediaKind = .unknown
        var showTitle: String?
        var showRatingKey: String?
        var showThumbPath: String?
        var seasonNumber: Int?
        var episodeNumber: Int?
        var episodeTitle: String?
        var thumbPath: String?
    }

    private func fetchEnqueueMetadata(
        server: PlexServer,
        ratingKey: String,
        title: String
    ) async -> EnqueueMetadata {
        guard server.usesLivePlexAPI else {
            if let inferred = OfflineDownloadRecord.inferKindForMigration(title: title) {
                return EnqueueMetadata(
                    mediaKind: .episode,
                    showTitle: inferred.showTitle,
                    seasonNumber: inferred.season,
                    episodeNumber: inferred.episode
                )
            }
            return EnqueueMetadata(mediaKind: .movie)
        }
        guard let client = try? PlexMediaServerClient(server: server),
              let detail = try? await client.fetchMediaDetail(ratingKey: ratingKey)
        else {
            return EnqueueMetadata(mediaKind: .movie)
        }
        var meta = EnqueueMetadata(thumbPath: detail.thumbPath)
        switch detail.node {
        case .movie:
            meta.mediaKind = .movie
        case .episode(let episode):
            meta.mediaKind = .episode
            meta.showTitle = episode.showTitle
            meta.showRatingKey = episode.showRatingKey
            meta.showThumbPath = episode.showThumbPath
            meta.seasonNumber = episode.seasonNumber
            meta.episodeNumber = episode.episodeNumber
            meta.episodeTitle = episode.title
            if (meta.showThumbPath == nil || meta.showThumbPath?.isEmpty == true),
               let showKey = episode.showRatingKey, !showKey.isEmpty,
               let showDetail = try? await client.fetchMediaDetail(ratingKey: showKey),
               let showThumb = showDetail.thumbPath, !showThumb.isEmpty {
                meta.showThumbPath = showThumb
            }
        default:
            meta.mediaKind = .movie
        }
        return meta
    }
}

// MARK: - Progress-reporting URLSession download

private final class OfflineDownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let recordID: UUID
    let recordTitle: String
    let destination: URL
    weak var manager: OfflineDownloadManager?
    var continuation: CheckedContinuation<Void, Error>?
    weak var downloadTask: URLSessionDownloadTask?

    private var lastBytesWritten: Int64 = 0
    private var lastSpeedSampleAt = Date()

    init(
        recordID: UUID,
        recordTitle: String,
        destination: URL,
        manager: OfflineDownloadManager,
        continuation: CheckedContinuation<Void, Error>
    ) {
        self.recordID = recordID
        self.recordTitle = recordTitle
        self.destination = destination
        self.manager = manager
        self.continuation = continuation
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        let now = Date()
        let elapsed = max(now.timeIntervalSince(lastSpeedSampleAt), 0.001)
        let delta = max(0, totalBytesWritten - lastBytesWritten)
        let speed = Double(delta) / elapsed
        lastBytesWritten = totalBytesWritten
        lastSpeedSampleAt = now

        Task { @MainActor [weak self] in
            guard let self, let manager = self.manager else { return }
            manager.updateDownloadProgress(
                recordID: self.recordID,
                recordTitle: self.recordTitle,
                bytesWritten: totalBytesWritten,
                expectedBytes: expected,
                speedBytesPerSecond: speed
            )
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Must move `location` before this method returns — URLSession deletes the temp file afterward.
        let result: Result<Void, Error> = Result {
            if let http = downloadTask.response as? HTTPURLResponse,
               !(200 ..< 300).contains(http.statusCode) {
                throw PlexAPIError.httpStatus(code: http.statusCode, bodySnippet: nil)
            }
            let parent = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            try OfflineDownloadFileValidator.validate(at: destination)
        }
        Task { @MainActor [weak self] in
            self?.resumeOnce(with: result)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor [weak self] in
            self?.resumeOnce(with: .failure(error))
        }
    }

    @MainActor
    private func resumeOnce(with result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
