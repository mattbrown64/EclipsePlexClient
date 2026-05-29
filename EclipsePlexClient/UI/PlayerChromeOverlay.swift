//
//  PlayerChromeOverlay.swift
//  EclipsePlexClient
//

import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Circular icon-only control for playback chrome (accessibility label only, no visible text).
struct PlaybackChromeIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Groups playback controls in a material pill with a visible capsule outline.
private struct PlaybackChromeCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.32), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
    }
}

extension View {
    func playbackChromeCapsule() -> some View {
        modifier(PlaybackChromeCapsuleModifier())
    }
}

/// Top/bottom playback chrome (auto-hide with `PlayerChromeController`).
struct PlayerChromeOverlay<TopTrailing: View, Bottom: View>: View {
    let title: String?
    var skipMarkerTitle: String?
    var onSkipMarker: () -> Void = {}
    let onExit: () -> Void
    var onMinimize: (() -> Void)?
    let onInteraction: () -> Void
    /// Tap on the empty area between top and bottom chrome (e.g. hide controls).
    var onBackgroundTap: () -> Void = {}
    @ViewBuilder let topTrailing: () -> TopTrailing
    @ViewBuilder let bottom: () -> Bottom

    var body: some View {
        GeometryReader { geometry in
            let insets = playbackChromeInsets(in: geometry)
            ZStack {
                VStack(spacing: 0) {
                    topChrome(insets: insets)
                    Spacer()
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onBackgroundTap)
                    bottomChrome(insets: insets)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private func playbackChromeInsets(in geometry: GeometryProxy) -> EdgeInsets {
#if os(iOS)
        PlaybackViewportInsets.chromeInsets(in: geometry)
#else
        geometry.safeAreaInsets
#endif
    }

    private func topChrome(insets: EdgeInsets) -> some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 8) {
                if let onMinimize {
                    PlaybackChromeIconButton(
                        systemImage: "chevron.down",
                        accessibilityLabel: "Minimize",
                        action: {
                            onInteraction()
                            onMinimize()
                        }
                    )
                    .accessibilityIdentifier("minimizePlayback")
                }

                PlaybackChromeIconButton(
                    systemImage: "xmark",
                    accessibilityLabel: "Stop",
                    action: {
                        onInteraction()
                        onExit()
                    }
                )
                .accessibilityIdentifier("exitPlayback")
            }

            VStack(spacing: 8) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                if let skipMarkerTitle {
                    Button(skipMarkerTitle, action: {
                        onInteraction()
                        onSkipMarker()
                    })
                    .buttonStyle(.pressableBorderedProminent)
                    .platformControlSize(.regular)
                    .accessibilityIdentifier("skipMarkerButton")
                }
            }
            .frame(maxWidth: .infinity)

            topTrailing()
                .frame(minWidth: 44, alignment: .trailing)
        }
        .playbackChromeCapsule()
        .padding(.horizontal, 16)
        .padding(.top, max(insets.top, 12))
        .padding(.leading, insets.leading)
        .padding(.trailing, insets.trailing)
    }

    private func bottomChrome(insets: EdgeInsets) -> some View {
        bottom()
            .playbackChromeCapsule()
            .padding(.horizontal, 16)
            .padding(.bottom, max(insets.bottom, 12))
            .padding(.leading, insets.leading)
            .padding(.trailing, insets.trailing)
    }
}
