//
//  PseudoTVCoordinator.swift
//  EclipsePlexClient
//

import Combine
import Foundation

/// Builds and maintains Pseudo-TV channels and schedules for one Plex server.
@MainActor
final class PseudoTVCoordinator: ObservableObject {
    @Published private(set) var channels: [PseudoTVChannel] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let server: PlexServer
    private let registry: PlexServerRegistry
    private var index: PseudoTVLibraryIndex?
    private var schedules: [String: PseudoTVScheduleSnapshot] = [:]

    init(server: PlexServer, registry: PlexServerRegistry) {
        self.server = server
        self.registry = registry
        channels = PseudoTVScheduleStore.loadChannels(serverId: server.id)
            .filter { !$0.isHidden }
        loadSchedulesFromDisk()
    }

    func refreshAll(force: Bool = false) async {
        guard server.usesLivePlexAPI else {
            errorMessage = "Server needs a valid URL and token."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let prepared = server.withTokenFromKeychain().withActiveConnection()
            let client = try PlexMediaServerClient(server: prepared)
            let libraries = registry.librariesByServerID[server.id] ?? []
            guard !libraries.isEmpty else {
                errorMessage = "No libraries loaded for this server."
                return
            }
            let builtIndex = try await PseudoTVLibraryIndexer.buildIndex(
                server: prepared,
                libraries: libraries,
                client: client
            )
            index = builtIndex
            var nextChannels = PseudoTVChannelFactory.makeChannels(serverId: server.id, index: builtIndex)
            let existing = PseudoTVScheduleStore.loadChannels(serverId: server.id)
            for i in nextChannels.indices {
                if let match = existing.first(where: { $0.id == nextChannels[i].id }) {
                    nextChannels[i].isHidden = match.isHidden
                    nextChannels[i].cycleGeneration = match.cycleGeneration
                }
            }
            channels = nextChannels.filter { !$0.isHidden }
            PseudoTVScheduleStore.saveChannels(nextChannels, serverId: server.id)
            for channel in channels {
                if force || schedules[channel.id] == nil
                    || schedules[channel.id].map({ PseudoTVProgramResolver.cycleHasElapsed(snapshot: $0) }) == true {
                    await rebuildSchedule(for: channel, index: builtIndex)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rebuildSchedule(for channel: PseudoTVChannel, index: PseudoTVLibraryIndex? = nil) async {
        let idx = index ?? self.index
        guard let idx else { return }
        var ch = channel
        ch.cycleGeneration += 1
        let programs = PseudoTVChannelFactory.programs(for: ch, index: idx)
        guard let snapshot = PseudoTVWeeklyGridBuilder.build(
            channel: ch,
            programs: programs,
            cycleGeneration: ch.cycleGeneration
        ) else { return }
        schedules[channel.id] = snapshot
        PseudoTVScheduleStore.saveSchedule(snapshot)
        if let i = channels.firstIndex(where: { $0.id == channel.id }) {
            channels[i].cycleGeneration = ch.cycleGeneration
        }
    }

    func nowPlaying(for channel: PseudoTVChannel, at date: Date = Date()) -> PseudoTVNowPlayingInfo? {
        guard let snapshot = schedules[channel.id] ?? PseudoTVScheduleStore.loadSchedule(channelId: channel.id)
        else { return nil }
        schedules[channel.id] = snapshot
        return PseudoTVProgramResolver.nowPlaying(at: date, snapshot: snapshot)
    }

    func tuneIn(for channel: PseudoTVChannel, at date: Date = Date()) -> PlaybackRequest? {
        guard let snapshot = schedules[channel.id] ?? PseudoTVScheduleStore.loadSchedule(channelId: channel.id),
              let resolved = PseudoTVProgramResolver.slot(at: date, snapshot: snapshot),
              let prepared = registry.allServers.first(where: { $0.id == server.id })?
                .withTokenFromKeychain().withActiveConnection()
        else { return nil }
        return PlaybackRequest.plex(
            server: prepared,
            ratingKey: resolved.slot.program.ratingKey,
            title: "\(channel.name) · \(resolved.slot.program.title)",
            episodeContext: nil,
            startFromBeginning: false,
            plexResumePositionMs: resolved.offsetMs,
            tuneInMode: .pseudoTVLive
        )
    }

    private func loadSchedulesFromDisk() {
        for channel in channels {
            if let snap = PseudoTVScheduleStore.loadSchedule(channelId: channel.id) {
                schedules[channel.id] = snap
            }
        }
    }
}
