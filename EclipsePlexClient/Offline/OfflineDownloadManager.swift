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
    @Published private(set) var records: [OfflineDownloadRecord] = [] {
        didSet { rebuildPlayableRatingKeyIndex() }
    }
    /// Bumped on every `persist()` (including throttled progress writes).
    /// Useful for "any record changed at all" subscribers, but **do not** key
    /// view reloads off this — it ticks ~every 2s during downloads.
    @Published private(set) var catalogRevision = 0
    /// Bumped only when the offline catalog's *shape* changes (add / remove /
    /// state transition / metadata mutation). Use this for `.task(id:)` reload
    /// keys so browsing offline content during an active download doesn't
    /// cancel and restart navigation loaders on every progress persist tick.
    @Published private(set) var catalogStructureRevision = 0
    @Published private(set) var isOnWiFi = true
    @Published private(set) var persistError: String?

    /// O(1) lookup index of playable downloads, keyed by server. Recomputed
    /// whenever `records` changes; lets `isDownloaded` avoid the per-cell linear
    /// scan that previously dominated catalog scroll cost.
    @Published private(set) var playableRatingKeysByServer: [UUID: Set<String>] = [:]

    /// Cached sum of on-disk download sizes. Recomputed only when `records`
    /// changes; avoids the per-`body` storm of `FileManager.attributesOfItem`
    /// stat calls that previously happened for every settings / downloads-list
    /// re-render.
    @Published private(set) var cachedTotalDownloadedBytes: Int64 = 0

    /// Live, high-frequency progress is published from a separate object so that
    /// per-byte updates do not republish `records` and re-render every screen
    /// observing the download manager.
    let progressStore = DownloadProgressStore()

    private var activeDownloadID: UUID?
    private var activeDownloadSession: URLSession?
    private var activeDownloadDelegate: OfflineDownloadSessionDelegate?
    private var lastProgressLogAt: [UUID: Date] = [:]
    private var lastPersistAt: [UUID: Date] = [:]
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "OfflineDownloadManager.path")
    private var serverResolver: (() -> [PlexServer])?
    /// Awaited by `configure(registry:)` so the post-launch work (scrobble
    /// flush, backfill, queue pump) runs only after the initial disk load is
    /// reflected in `records`.
    private var initialLoadTask: Task<Void, Never>?

    init() {
        rebuildPlayableRatingKeyIndex()
        startPathMonitor()
        // Disk JSON load + per-file validation moved off the main actor so
        // launching the app no longer blocks on the downloads store. UI sees
        // an empty download list for one runloop and is populated when the
        // detached task completes.
        initialLoadTask = Task { @MainActor [weak self] in
            let loaded = await Task.detached(priority: .userInitiated) {
                OfflineDownloadStore.load()
            }.value
            guard let self else { return }
            self.records = loaded
            self.reconcileStaleDownloads()
        }
    }

    /// Last-known "catalog shape" signature, used to decide whether a `records`
    /// mutation should bump `catalogStructureRevision`. The signature is just
    /// `(id, state, ratingKey, title, completedAt)` per record — anything that
    /// alters how the offline catalog *displays*. Progress bytes / errors are
    /// deliberately excluded so download ticks don't trigger reloads.
    private var lastCatalogStructureSignature: String = ""
    /// Coalesces async size-walk requests so rapid `records` mutations don't
    /// spawn N parallel detached stat walks.
    private var pendingTotalBytesRecompute: Task<Void, Never>?

    private func rebuildPlayableRatingKeyIndex() {
        var map: [UUID: Set<String>] = [:]
        var signatureParts: [String] = []
        signatureParts.reserveCapacity(records.count)
        for record in records {
            if record.isPlayable {
                map[record.serverId, default: []].insert(record.ratingKey)
            }
            signatureParts.append(
                "\(record.id.uuidString)|\(record.state.rawValue)|\(record.ratingKey)|\(record.title)|\(record.completedAt?.timeIntervalSince1970 ?? 0)"
            )
        }
        playableRatingKeysByServer = map

        let signature = signatureParts.joined(separator: ";")
        if signature != lastCatalogStructureSignature {
            lastCatalogStructureSignature = signature
            catalogStructureRevision &+= 1
            // Only the shape-changing transitions need to revalidate the
            // on-disk size (new download completed, item deleted, etc.).
            // Progress persist ticks now skip the stat walk entirely.
            scheduleTotalBytesRecompute()
        }
    }

    /// Schedules an off-main `FileManager.attributesOfItem` walk to recompute
    /// `cachedTotalDownloadedBytes`. Previously the stat walk ran inline in
    /// `records.didSet`, which meant every batched progress mutation paid for
    /// N FileManager stat calls on the main actor. Now it's coalesced and
    /// detached at `.utility`.
    private func scheduleTotalBytesRecompute() {
        pendingTotalBytesRecompute?.cancel()
        let recordsSnapshot = records
        pendingTotalBytesRecompute = Task { @MainActor [weak self] in
            // Brief coalescing window so back-to-back didSet calls collapse.
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, let self else { return }
            let total = await Task.detached(priority: .utility) {
                Self.computeTotalDownloadedBytes(for: recordsSnapshot)
            }.value
            guard !Task.isCancelled else { return }
            self.cachedTotalDownloadedBytes = total
        }
    }

    /// Pure helper safe to run off the main actor. Mirrors the path-resolution
    /// rules in `localFileURL(for:)` so the off-main walk doesn't need actor-
    /// isolated access to `self`.
    private nonisolated static func computeTotalDownloadedBytes(for records: [OfflineDownloadRecord]) -> Int64 {
        var total: Int64 = 0
        let downloadsDir = OfflineDownloadStore.downloadsDirectory
        for record in records {
            guard let relative = record.relativeFilePath else { continue }
            let url = downloadsDir.appendingPathComponent(relative)
            if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64 {
                total &+= size
            }
        }
        return total
    }

    deinit {
        pathMonitor?.cancel()
    }

    func configure(registry: PlexServerRegistry) {
        serverResolver = { registry.allServers }
        Task { [weak self] in
            // Wait for the off-main initial load + reconcile to finish before
            // touching `records` for scrobble flush / thumb backfill / queue pump.
            await self?.initialLoadTask?.value
            OfflineScrobbleQueue.scheduleFlush(servers: registry.allServers)
            await self?.backfillMissingThumbs()
            await self?.pumpQueue()
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
        playableRatingKeysByServer[serverId]?.contains(ratingKey) ?? false
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
        cachedTotalDownloadedBytes
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
        progressStore.remove(id: id)
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
        let ids = Set(records.filter { $0.showGroupKey == groupKey }.map(\.id))
        deleteIDs(ids)
    }

    func delete(id: UUID) {
        deleteIDs([id])
    }

    /// Removes all completed download files.
    func deleteAllCompleted() {
        let ids = Set(records.filter { $0.state == .completed }.map(\.id))
        deleteIDs(ids)
    }

    /// Bulk delete that performs file removal up front and then rewrites the
    /// records array exactly once, so the playable-key index rebuild and the
    /// disk persist only run a single time for the whole batch.
    private func deleteIDs(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let urls = records
            .filter { ids.contains($0.id) }
            .compactMap { localFileURL(for: $0) }
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
        batchMutateRecords { recs in
            recs.removeAll { ids.contains($0.id) }
        }
    }

    /// Re-queues failed downloads.
    func retryFailedDownloads() {
        batchMutateRecords { recs in
            for index in recs.indices where recs[index].state == .failed {
                recs[index].state = .pending
                recs[index].errorMessage = nil
            }
        }
        Task { await pumpQueue() }
    }

    /// Single-write batch mutator. Folds N record changes into one `records`
    /// assignment so the `didSet`-driven index rebuild and disk persist each
    /// run once per logical operation instead of once per mutated row.
    private func batchMutateRecords(
        persist shouldPersist: Bool = true,
        _ block: (inout [OfflineDownloadRecord]) -> Void
    ) {
        var copy = records
        block(&copy)
        records = copy
        if shouldPersist {
            persist()
        }
    }

    var totalDownloadBytes: Int64 {
        cachedTotalDownloadedBytes
    }

    func server(for record: OfflineDownloadRecord) -> PlexServer? {
        servers().first { $0.id == record.serverId }
    }

    func transferSpeed(for recordID: UUID) -> Double? {
        progressStore.speed(for: recordID)
    }

    /// Returns the most up-to-date progress snapshot, preferring the live store
    /// (active downloads) and falling back to the persisted record fields.
    func liveProgress(for record: OfflineDownloadRecord) -> DownloadProgressStore.Snapshot {
        if let live = progressStore.snapshot(for: record.id) {
            return live
        }
        return DownloadProgressStore.Snapshot(
            bytesWritten: record.bytesWritten,
            expectedBytes: record.expectedBytes,
            progress: record.progress,
            speedBytesPerSecond: 0
        )
    }

    func pumpQueueIfAllowed() async {
        await pumpQueue()
    }

    func retry(id: UUID) {
        progressStore.remove(id: id)
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
            let completedTitle = next.title
            persist()
            Task {
                await OfflineDownloadNotifications.scheduleCompletionNotification(title: completedTitle)
            }
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
        AppLog.offline("Download started: \(title)")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = OfflineDownloadSessionDelegate(
                recordID: recordID,
                recordTitle: title,
                destination: destination,
                manager: self,
                continuation: continuation
            )
            let session = Self.makeDownloadURLSession(delegate: delegate)
            activeDownloadDelegate = delegate
            activeDownloadSession = session
            let task = session.downloadTask(with: request)
            delegate.downloadTask = task
            task.resume()
        }
        tearDownActiveDownloadSession()
        progressStore.remove(id: recordID)
        lastProgressLogAt.removeValue(forKey: recordID)
        lastPersistAt.removeValue(forKey: recordID)

        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
        updateRecord(id: recordID) {
            $0.bytesWritten = size
            $0.expectedBytes = size > 0 ? size : $0.expectedBytes
            $0.progress = 1
        }
        AppLog.offline("Download finished: \(title) · \(OfflineDownloadProgressFormatter.bytes(size))")
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

        // High-frequency: only the progress store publishes here. The `records`
        // array is *not* mutated each tick (which would republish to every
        // screen observing the download manager).
        progressStore.update(
            id: recordID,
            snapshot: DownloadProgressStore.Snapshot(
                bytesWritten: bytesWritten,
                expectedBytes: expectedBytes,
                progress: progress,
                speedBytesPerSecond: speedBytesPerSecond
            )
        )

        let now = Date()
        if now.timeIntervalSince(lastProgressLogAt[recordID] ?? .distantPast) >= 1 {
            lastProgressLogAt[recordID] = now
            AppLog.offlineDebug(
                "Download \(recordTitle): \(OfflineDownloadProgressFormatter.percent(progress)) · \(OfflineDownloadProgressFormatter.speed(speedBytesPerSecond))"
            )
        }

        // Low-frequency: sync the snapshot into the persisted record every ~2s
        // so a crash/quit during a download still resumes with an accurate
        // progress bar after re-launch.
        if now.timeIntervalSince(lastPersistAt[recordID] ?? .distantPast) >= 2 {
            lastPersistAt[recordID] = now
            updateRecord(id: recordID) {
                $0.bytesWritten = bytesWritten
                $0.progress = progress
                if let expectedBytes, expectedBytes > 0 {
                    $0.expectedBytes = expectedBytes
                }
            }
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
        batchMutateRecords(persist: false) { recs in
            for index in recs.indices {
                guard recs[index].state == .completed else { continue }
                guard let path = recs[index].relativeFilePath else {
                    recs[index].state = .failed
                    recs[index].errorMessage = "Download file is missing."
                    changed = true
                    continue
                }
                let url = OfflineDownloadStore.downloadsDirectory.appendingPathComponent(path)
                do {
                    try OfflineDownloadFileValidator.validate(at: url)
                } catch {
                    recs[index].state = .failed
                    recs[index].errorMessage = error.localizedDescription
                    changed = true
                }
            }
        }
        if changed {
            persist()
        }
    }

    private func fail(id: UUID, message: String) {
        let title = records.first(where: { $0.id == id })?.title ?? id.uuidString
        AppLog.offline("Download failed: \(title) — \(message)")
        progressStore.remove(id: id)
        lastProgressLogAt.removeValue(forKey: id)
        lastPersistAt.removeValue(forKey: id)
        updateRecord(id: id) {
            $0.state = .failed
            $0.errorMessage = message
        }
        persist()
        activeDownloadID = nil
        Task {
            await OfflineDownloadNotifications.scheduleFailureNotification(title: title, message: message)
        }
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
        do {
            try OfflineDownloadStore.save(records)
            persistError = nil
            catalogRevision &+= 1
        } catch {
            persistError = error.localizedDescription
            CrashReporter.record(message: "Offline persist failed: \(error.localizedDescription)", category: "offline")
            AppLog.offline("Persist failed: \(error.localizedDescription)")
        }
    }

    private static func makeDownloadURLSession(delegate: URLSessionDownloadDelegate) -> URLSession {
        #if os(iOS)
        URLSession(configuration: OfflineDownloadBackgroundSession.makeConfiguration(), delegate: delegate, delegateQueue: nil)
        #else
        URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        #endif
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

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        #if os(iOS)
        let completion = OfflineDownloadBackgroundSession.backgroundCompletionHandler
        OfflineDownloadBackgroundSession.backgroundCompletionHandler = nil
        completion?()
        #endif
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
