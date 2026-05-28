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
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
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
                    .controlSize(.regular)
                    .accessibilityIdentifier("skipMarkerButton")
                }
            }
            .frame(maxWidth: .infinity)

            topTrailing()
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .padding(.top, insets.top)
        .padding(.leading, insets.leading)
        .padding(.trailing, insets.trailing)
    }

    private func bottomChrome(insets: EdgeInsets) -> some View {
        bottom()
            .padding(.bottom, insets.bottom)
            .padding(.leading, insets.leading)
            .padding(.trailing, insets.trailing)
    }
}
