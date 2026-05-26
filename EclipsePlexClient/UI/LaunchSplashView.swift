//
//  LaunchSplashView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Simple launch splash shown while the app is bootstrapping.
struct LaunchSplashView: View {
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Use the in-app logo asset; visually aligns with the app icon
                // and avoids coupling to the app icon asset catalog.
                EclipsePlexLogo(style: .hero)

                ProgressView("Loading…")
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
            .padding()
        }
    }
}

#Preview {
    LaunchSplashView()
}

