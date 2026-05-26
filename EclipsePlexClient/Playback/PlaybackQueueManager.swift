//
//  PlaybackQueueManager.swift
//  EclipsePlexClient
//

import Combine
import Foundation

/// In-session play queue (Up Next) beyond single episode auto-advance.
@MainActor
final class PlaybackQueueManager: ObservableObject {
    @Published private(set) var items: [PlaybackQueueItem] = []
    @Published private(set) var currentIndex: Int?

    var isEmpty: Bool { items.isEmpty }
    var hasNext: Bool {
        guard let currentIndex, currentIndex + 1 < items.count else { return !items.isEmpty && currentIndex == nil }
        return currentIndex + 1 < items.count
    }

    func replaceAll(_ newItems: [PlaybackQueueItem], startAt index: Int = 0) {
        items = newItems
        currentIndex = newItems.isEmpty ? nil : min(max(0, index), newItems.count - 1)
    }

    func enqueue(_ item: PlaybackQueueItem) {
        items.append(item)
        if currentIndex == nil, !items.isEmpty { currentIndex = 0 }
    }

    func shuffle() {
        guard items.count > 1 else { return }
        let current = currentItem
        items.shuffle()
        if let current, let idx = items.firstIndex(where: { $0.id == current.id }) {
            currentIndex = idx
        } else {
            currentIndex = 0
        }
    }

    var currentItem: PlaybackQueueItem? {
        guard let currentIndex, items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    func advance() -> PlaybackQueueItem? {
        guard let idx = currentIndex else {
            if !items.isEmpty {
                currentIndex = 0
                return items[0]
            }
            return nil
        }
        let next = idx + 1
        guard items.indices.contains(next) else { return nil }
        currentIndex = next
        return items[next]
    }

    func clear() {
        items = []
        currentIndex = nil
    }
}

struct PlaybackQueueItem: Identifiable, Hashable, Sendable {
    let id: String
    let serverId: UUID
    let ratingKey: String
    let title: String
    let episodeContext: EpisodePlayContext?

    init(
        serverId: UUID,
        ratingKey: String,
        title: String,
        episodeContext: EpisodePlayContext? = nil
    ) {
        self.id = "\(serverId.uuidString)|\(ratingKey)"
        self.serverId = serverId
        self.ratingKey = ratingKey
        self.title = title
        self.episodeContext = episodeContext
    }
}
