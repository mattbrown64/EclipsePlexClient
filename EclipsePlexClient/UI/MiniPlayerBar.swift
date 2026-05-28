//
//  MiniPlayerBar.swift
//  EclipsePlexClient
//

import SwiftUI

/// Persistent transport chrome shown while browsing during an active playback session.
struct MiniPlayerBar: View {
    @ObservedObject var presenter: PlaybackPresenter
    @Environment(\.themeAccent) private var themeAccent

    private var progress: Double {
        guard presenter.durationMs > 0 else { return 0 }
        return min(1, max(0, Double(presenter.positionMs) / Double(presenter.durationMs)))
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(themeAccent)
                .frame(height: 2)

            HStack(spacing: 12) {
                Button(action: { presenter.expand() }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(presenter.sessionTitle ?? "Playing")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(statusSubtitle)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("miniPlayerExpand")

                Button(action: { presenter.togglePlayPause() }) {
                    Image(systemName: presenter.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("miniPlayerPlayPause")

                Button(action: { presenter.stop() }) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("miniPlayerStop")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
#if os(tvOS)
        .background(.regularMaterial)
#else
        .background(.bar)
#endif
        .accessibilityIdentifier("miniPlayerBar")
    }

    private var formattedRemaining: String {
        guard presenter.durationMs > 0 else { return "—" }
        let remaining = max(0, presenter.durationMs - presenter.positionMs)
        return Self.format(ms: remaining) + " left"
    }

    private var statusSubtitle: String {
        if presenter.isPlaying {
            return formattedRemaining
        }
        return "Buffering…"
    }

    private static func format(ms: Int) -> String {
        let totalSeconds = ms / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
