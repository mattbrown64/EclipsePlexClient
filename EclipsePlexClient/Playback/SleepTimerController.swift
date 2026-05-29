//
//  SleepTimerController.swift
//  EclipsePlexClient
//

import Combine
import Foundation

/// Pauses playback after a deadline or when the current episode ends.
@MainActor
final class SleepTimerController: ObservableObject {
    enum Mode: Equatable {
        case none
        case wallClock(end: Date)
        case afterEpisode
    }

    @Published private(set) var mode: Mode = .none
    @Published private(set) var remainingSeconds: Int?

    private var tickTask: Task<Void, Never>?

    func start(minutes: Int) {
        cancel()
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        mode = .wallClock(end: end)
        scheduleTick()
    }

    func startAfterEpisode() {
        cancel()
        mode = .afterEpisode
        remainingSeconds = nil
    }

    func cancel() {
        tickTask?.cancel()
        tickTask = nil
        mode = .none
        remainingSeconds = nil
    }

    var shouldStopAfterEpisode: Bool {
        mode == .afterEpisode
    }

    private func scheduleTick() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self?.updateRemaining()
            }
        }
    }

    private func updateRemaining() {
        guard case .wallClock(let end) = mode else { return }
        let left = Int(end.timeIntervalSinceNow)
        if left <= 0 {
            remainingSeconds = 0
            cancel()
        } else {
            remainingSeconds = left
        }
    }
}
