//
//  AppToastCenter.swift
//  EclipsePlexClient
//

import Combine
import SwiftUI

/// Brief user-visible messages (API/scrobble failures, etc.).
@MainActor
final class AppToastCenter: ObservableObject {
    static weak var shared: AppToastCenter?

    @Published private(set) var message: String?

    private var dismissTask: Task<Void, Never>?

    init() {
        Self.shared = self
    }

    static func show(_ text: String, durationSeconds: Double = 4) {
        shared?.show(text, durationSeconds: durationSeconds)
    }

    func show(_ text: String, durationSeconds: Double = 4) {
        message = text
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(durationSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if message == text {
                message = nil
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        message = nil
    }
}

private struct AppToastBanner: View {
    @ObservedObject var center: AppToastCenter
    @EnvironmentObject private var playbackPresenter: PlaybackPresenter

    private var suppressForFullscreenPlayback: Bool {
        playbackPresenter.hasActiveSession && playbackPresenter.presentationMode == .fullScreen
    }

    var body: some View {
        if let message = center.message, !suppressForFullscreenPlayback {
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { center.dismiss() }
        }
    }
}

extension View {
    func appToastOverlay(_ center: AppToastCenter) -> some View {
        overlay(alignment: .top) {
            AppToastBanner(center: center)
                .padding(.top, 8)
                .animation(.easeInOut(duration: 0.2), value: center.message)
        }
    }
}
