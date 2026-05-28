//
//  LaunchSplashView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Simple launch splash shown while the app is bootstrapping.
struct LaunchSplashView: View {
    @Environment(\.appThemePalette) private var themePalette
    @Environment(\.themeAccent) private var themeAccent

    var body: some View {
        ZStack {
            if let palette = themePalette {
                let (start, end) = palette.playerGradientPoints
                LinearGradient(colors: palette.playerGradient, startPoint: start, endPoint: end)
                    .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
            }

            VStack(spacing: 20) {
                EclipsePlexLogo(style: .hero)

                ProgressView("Loading…")
                    .progressViewStyle(.circular)
                    .tint(themeAccent)
            }
            .padding()
        }
    }
}

#Preview {
    LaunchSplashView()
}

