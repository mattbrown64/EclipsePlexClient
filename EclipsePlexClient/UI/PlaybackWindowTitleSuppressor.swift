//
//  PlaybackWindowTitleSuppressor.swift
//  EclipsePlexClient
//

import SwiftUI

#if os(macOS)
import AppKit

/// Hides the macOS window title beside the traffic-light buttons during playback.
/// SwiftUI `navigationTitle` updates the toolbar/titlebar, not only `NSWindow.title`.
@MainActor
final class PlaybackWindowTitleController {
    static let shared = PlaybackWindowTitleController()

    private var isSuppressed = false
    private var savedTitle: String?
    private var savedTitleVisibility: NSWindow.TitleVisibility?
    private var titleObservation: NSKeyValueObservation?
    private var refreshTimer: Timer?
    private weak var window: NSWindow?

    private init() {}

    func setSuppressed(_ suppressed: Bool) {
        if suppressed {
            guard !isSuppressed else {
                apply()
                return
            }
            isSuppressed = true
            captureWindow()
            saveStateIfNeeded()
            startObserving()
            startRefreshTimer()
            apply()
        } else {
            guard isSuppressed else { return }
            isSuppressed = false
            stopRefreshTimer()
            stopObserving()
            restore()
        }
    }

    private func captureWindow() {
        window = NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey })
    }

    private func saveStateIfNeeded() {
        guard let window else { return }
        if savedTitle == nil {
            savedTitle = window.title
            savedTitleVisibility = window.titleVisibility
        }
    }

    private func startObserving() {
        guard titleObservation == nil, let window else { return }
        titleObservation = window.observe(\.title, options: [.new]) { [weak self] window, _ in
            Task { @MainActor in
                guard self?.isSuppressed == true else { return }
                if !window.title.isEmpty {
                    window.title = ""
                    window.titleVisibility = .hidden
                }
                self?.hideTitlebarLabels(in: window)
            }
        }
    }

    private func stopObserving() {
        titleObservation?.invalidate()
        titleObservation = nil
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.apply()
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func apply() {
        captureWindow()
        guard let window else { return }
        saveStateIfNeeded()
        window.title = ""
        window.titleVisibility = .hidden
        hideTitlebarLabels(in: window)
    }

    private func restore() {
        captureWindow()
        guard let window else {
            savedTitle = nil
            savedTitleVisibility = nil
            self.window = nil
            return
        }
        if let savedTitle {
            window.title = savedTitle
        }
        if let savedTitleVisibility {
            window.titleVisibility = savedTitleVisibility
        }
        showTitlebarLabels(in: window)
        savedTitle = nil
        savedTitleVisibility = nil
        self.window = nil
    }

    private func hideTitlebarLabels(in window: NSWindow) {
        for view in titlebarContentViews(in: window) {
            view.isHidden = true
            view.alphaValue = 0
        }
    }

    private func showTitlebarLabels(in window: NSWindow) {
        for view in titlebarContentViews(in: window) {
            view.isHidden = false
            view.alphaValue = 1
        }
    }

    /// Views in the titlebar strip that carry the movie/show name (SwiftUI toolbar title).
    private func titlebarContentViews(in window: NSWindow) -> [NSView] {
        guard let close = window.standardWindowButton(.closeButton) else { return [] }
        let mini = window.standardWindowButton(.miniaturizeButton)
        let zoom = window.standardWindowButton(.zoomButton)
        let trafficLights = Set([close, mini, zoom].compactMap { $0 }.map { ObjectIdentifier($0) })

        var results: [NSView] = []
        var queue: [NSView] = [close]
        var visited = Set<ObjectIdentifier>()
        var depth = 0

        while !queue.isEmpty, depth < 10 {
            let batch = queue
            queue.removeAll(keepingCapacity: true)
            depth += 1
            for view in batch {
                let id = ObjectIdentifier(view)
                guard visited.insert(id).inserted else { continue }

                if trafficLights.contains(id) || view is NSButton {
                    continue
                }

                let typeName = String(describing: type(of: view))
                if view is NSTextField || view is NSText {
                    results.append(view)
                    continue
                }
                if typeName.contains("Title")
                    || typeName.contains("Toolbar")
                    || typeName.contains("Hosting") {
                    // SwiftUI title is often hosted in a small hosting view beside the traffic lights.
                    if view.fittingSize.width > 40, view.fittingSize.height > 10 {
                        results.append(view)
                    }
                }

                if let superview = view.superview {
                    queue.append(superview)
                }
                queue.append(contentsOf: view.subviews)
            }
        }
        return results
    }
}

/// Clears SwiftUI toolbar/window titles on the browse detail stack during playback.
private struct DetailColumnMacWindowTitlePolicy: ViewModifier {
    let suppressed: Bool

    func body(content: Content) -> some View {
        if suppressed {
            content
                .navigationTitle("")
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Color.clear.frame(width: 0, height: 0)
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    /// Stops the browse detail `NavigationStack` from publishing a title to the window toolbar.
    func detailColumnMacWindowTitlePolicy(suppressed: Bool) -> some View {
        modifier(DetailColumnMacWindowTitlePolicy(suppressed: suppressed))
    }

    /// Clears the macOS window title bar label while fullscreen playback is visible.
    func playbackSuppressesMacWindowTitle(_ active: Bool) -> some View {
        onChange(of: active) { _, isActive in
            PlaybackWindowTitleController.shared.setSuppressed(isActive)
        }
        .onAppear {
            PlaybackWindowTitleController.shared.setSuppressed(active)
        }
        .onDisappear {
            if active {
                PlaybackWindowTitleController.shared.setSuppressed(false)
            }
        }
    }
}
#endif
