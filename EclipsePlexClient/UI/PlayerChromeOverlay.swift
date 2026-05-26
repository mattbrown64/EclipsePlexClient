//
//  PlayerChromeOverlay.swift
//  EclipsePlexClient
//

import SwiftUI

/// Top/bottom playback chrome with gradient scrims (auto-hide with `PlayerChromeController`).
struct PlayerChromeOverlay<TopTrailing: View, Bottom: View>: View {
    let title: String?
    var skipMarkerTitle: String?
    var onSkipMarker: () -> Void = {}
    let onExit: () -> Void
    let onInteraction: () -> Void
    /// Tap on the empty area between top and bottom chrome (e.g. hide controls).
    var onBackgroundTap: () -> Void = {}
    @ViewBuilder let topTrailing: () -> TopTrailing
    @ViewBuilder let bottom: () -> Bottom

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topChrome
                Spacer()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onBackgroundTap)
                bottomChrome
            }
        }
        .transition(.opacity)
    }

    private var topChrome: some View {
        ZStack(alignment: .top) {
            PlayerChromeScrim(edge: .top)
            HStack(alignment: .top, spacing: 12) {
                Button(action: {
                    onInteraction()
                    onExit()
                }) {
                    Label("Exit", systemImage: "chevron.backward")
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)

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
            .padding()
            .padding(.top, 4)
        }
        .safeAreaPadding(.top)
    }

    private var bottomChrome: some View {
        ZStack(alignment: .bottom) {
            PlayerChromeScrim(edge: .bottom)
            bottom()
        }
#if os(iOS)
        .safeAreaPadding(.bottom, 8)
#endif
    }
}

private struct PlayerChromeScrim: View {
    enum Edge {
        case top
        case bottom
    }

    let edge: Edge

    var body: some View {
        LinearGradient(
            colors: [Color.black.opacity(0.55), Color.black.opacity(0)],
            startPoint: edge == .top ? .top : .bottom,
            endPoint: edge == .top ? .bottom : .top
        )
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .allowsHitTesting(false)
    }
}
