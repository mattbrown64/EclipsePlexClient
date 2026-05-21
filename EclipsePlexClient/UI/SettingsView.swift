//
//  SettingsView.swift
//  EclipsePlexClient
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var registry: PlexServerRegistry
    @EnvironmentObject private var downloadManager: OfflineDownloadManager

    @State private var defaultPlaybackSpeed: Float = PlaybackPreferences.loadPlaybackRate()
    @State private var downloadWifiOnly: Bool = OfflineDownloadPreferences.wifiOnly
    @State private var defaultDownloadQuality: PlaybackVideoResolution = OfflineDownloadPreferences.defaultQuality

    @State private var showSignOutConfirm = false
    @State private var showAddServer = false

    var body: some View {
        Form {
            Section("Playback") {
                Picker("Default speed", selection: $defaultPlaybackSpeed) {
                    ForEach(PlaybackSpeed.allCases) { speed in
                        Text(speed.menuTitle).tag(speed.rawValue)
                    }
                }
                .onChange(of: defaultPlaybackSpeed) { _, rate in
                    PlaybackPreferences.savePlaybackRate(rate)
                }
            }

            Section("Downloads") {
                Toggle("Wi‑Fi only", isOn: $downloadWifiOnly)
                    .onChange(of: downloadWifiOnly) { _, value in
                        OfflineDownloadPreferences.wifiOnly = value
                    }
                Picker("Default quality", selection: $defaultDownloadQuality) {
                    ForEach(PlaybackVideoResolution.allCases) { res in
                        Text(res.menuTitle).tag(res)
                    }
                }
                .onChange(of: defaultDownloadQuality) { _, value in
                    OfflineDownloadPreferences.defaultQuality = value
                }
                NavigationLink {
                    DownloadsHomeDetailView()
                        .environmentObject(downloadManager)
                } label: {
                    Label("Manage downloads", systemImage: "arrow.down.circle")
                }
            }

            Section("Plex account") {
                Button("Add Plex Server…") {
                    showAddServer = true
                }
                if registry.plexAccountAuthToken != nil {
                    Button("Sign out of Plex.tv", role: .destructive) {
                        showSignOutConfirm = true
                    }
                }
            }

            Section("About") {
                LabeledContent("App", value: EclipsePlexBranding.productName)
                LabeledContent("Version", value: PlexHTTPConstants.productVersion)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showAddServer) {
            AddPlexServerSheet(registry: registry)
        }
        .confirmDestructive(
            title: "Sign out of Plex.tv?",
            message: "This clears your Plex.tv token used for PIN sign-in. Saved servers on this device are not removed.",
            confirmLabel: "Sign Out",
            isPresented: $showSignOutConfirm
        ) {
            registry.setPlexAccountToken(nil)
        }
    }
}
