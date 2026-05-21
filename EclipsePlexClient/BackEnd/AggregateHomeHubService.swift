//
//  AggregateHomeHubService.swift
//  EclipsePlexClient
//

import Foundation

nonisolated struct AggregateHomeShelf: Sendable {
    let server: PlexServer
    let continueWatching: [PlexCatalogSearchHit]
    let recentlyAdded: [PlexCatalogSearchHit]
    let errorMessage: String?
}

private actor AggregateHomeHubCache {
    static let shared = AggregateHomeHubCache()

    private var entries: [UUID: (fetchedAt: Date, shelf: AggregateHomeShelf)] = [:]

    func cachedShelf(for serverId: UUID, ttl: TimeInterval) -> AggregateHomeShelf? {
        guard let entry = entries[serverId], Date().timeIntervalSince(entry.fetchedAt) < ttl else {
            return nil
        }
        return entry.shelf
    }

    func store(_ shelf: AggregateHomeShelf) {
        entries[shelf.server.id] = (Date(), shelf)
    }

    func invalidateAll() {
        entries.removeAll()
    }
}

nonisolated struct AggregateHomeHubService {
    static let cacheTTL: TimeInterval = 180
    private static let maxConcurrency = 4

    static func cachedShelf(for serverId: UUID) async -> AggregateHomeShelf? {
        await AggregateHomeHubCache.shared.cachedShelf(for: serverId, ttl: cacheTTL)
    }

    static func store(_ shelf: AggregateHomeShelf) async {
        await AggregateHomeHubCache.shared.store(shelf)
    }

    static func invalidateAll() async {
        await AggregateHomeHubCache.shared.invalidateAll()
    }

    static func load(
        servers: [PlexServer],
        librariesByServerID: [UUID: [PlexLibrary]]
    ) async -> [AggregateHomeShelf] {
        let live = servers.filter(\.usesLivePlexAPI)
        var shelves: [AggregateHomeShelf] = []
        var index = 0

        await withTaskGroup(of: AggregateHomeShelf.self) { group in
            func enqueue(_ server: PlexServer) {
                let libraries = librariesByServerID[server.id] ?? []
                group.addTask {
                    if let cached = await AggregateHomeHubCache.shared.cachedShelf(
                        for: server.id,
                        ttl: cacheTTL
                    ) {
                        return cached
                    }
                    let shelf = await fetchShelf(server: server, libraries: libraries)
                    await AggregateHomeHubCache.shared.store(shelf)
                    return shelf
                }
            }

            let initial = min(maxConcurrency, live.count)
            for _ in 0 ..< initial {
                enqueue(live[index])
                index += 1
            }

            for await shelf in group {
                shelves.append(shelf)
                if index < live.count {
                    enqueue(live[index])
                    index += 1
                }
            }
        }

        return shelves.sorted {
            $0.server.name.localizedCaseInsensitiveCompare($1.server.name) == .orderedAscending
        }
    }

    private static func fetchShelf(server: PlexServer, libraries: [PlexLibrary]) async -> AggregateHomeShelf {
        guard !libraries.isEmpty else {
            return AggregateHomeShelf(server: server, continueWatching: [], recentlyAdded: [], errorMessage: nil)
        }
        do {
            let client = try PlexMediaServerClient(server: server)
            async let onDeck = client.fetchOnDeckHits(libraries: libraries)
            async let recent = client.fetchRecentlyAddedHits(libraries: libraries)
            return AggregateHomeShelf(
                server: server,
                continueWatching: try await onDeck,
                recentlyAdded: try await recent,
                errorMessage: nil
            )
        } catch {
            return AggregateHomeShelf(
                server: server,
                continueWatching: [],
                recentlyAdded: [],
                errorMessage: error.localizedDescription
            )
        }
    }
}
