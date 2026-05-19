//
//  HomeDetailView.swift
//  EclipsePlexClient
//
//  Created by Matt Brown on 5/15/26.
//

import SwiftUI

/// Detail column when no library is selected — welcome / pick a library.
struct HomeDetailView: View {
    let plexServer: PlexServer?
    var onAddPlexServer: () -> Void = {}

    var body: some View {
        VStack(spacing: 20) {
            Text("Eclipse Plex")
                .font(.largeTitle.weight(.bold))
            Text("Welcome")
                .font(.title2)
                .foregroundStyle(.secondary)

            if let plexServer {
                HStack(spacing: 4) {
                    Text("Plex server:")
                        .foregroundStyle(.secondary)
                    Text(plexServer.name)
                        .fontWeight(.semibold)
                }
                .font(.body)
                Text("Choose a library in the sidebar to open it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Choose a Plex server in the sidebar, then a library.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                onAddPlexServer()
            } label: {
                Label("Add Plex Server", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Home")
    }
}

#Preview("Home — with server") {
    NavigationStack {
        HomeDetailView(plexServer: PlexSampleData.servers.first)
    }
}

#Preview("Home — no server") {
    NavigationStack {
        HomeDetailView(plexServer: nil)
    }
}
