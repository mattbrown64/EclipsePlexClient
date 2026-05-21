//
//  PlayerChromeController.swift
//  EclipsePlexClient
//

import Combine
import SwiftUI

/// Idle auto-hide and pin logic for playback chrome (transport, exit, settings).
@MainActor
final class PlayerChromeController: ObservableObject {
    @Published private(set) var isVisible = true

    var idleInterval: Duration = .seconds(3.5)

    private var hideTask: Task<Void, Never>?
    private var pinCount = 0

    var isPinned: Bool { pinCount > 0 }

    func show() {
        cancelHide()
        setVisible(true)
    }

    func hide() {
        guard !isPinned else { return }
        cancelHide()
        setVisible(false)
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            bumpActivity()
        }
    }

    /// Show chrome and restart the idle hide timer (unless pinned).
    func bumpActivity() {
        show()
        scheduleHideUnlessPinned()
    }

    /// Keep chrome visible while scrubbing, menus, or blocking overlays are active.
    func setPinned(_ pinned: Bool) {
        if pinned {
            if pinCount == 0 {
                cancelHide()
                show()
            }
            pinCount += 1
        } else {
            pinCount = max(0, pinCount - 1)
            if pinCount == 0 {
                scheduleHideUnlessPinned()
            }
        }
    }

    func tearDown() {
        cancelHide()
        pinCount = 0
    }

    private func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            isVisible = visible
        }
    }

    private func scheduleHideUnlessPinned() {
        cancelHide()
        guard !isPinned else { return }
        let interval = idleInterval
        hideTask = Task {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
    }
}
