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
    @State private var defaultVideoResolution: PlaybackVideoResolution = PlaybackPreferences.load().videoResolution
    @State private var preferDirectPlayLAN: Bool = PlaybackPreferences.preferDirectPlayOnLAN
    @State private var preferHLS: Bool = PlaybackPreferences.preferHLSTranscode

    @State private var showSignOutConfirm = false
    @State private var showAddServer = false
    @State private var showClearArtworkConfirm = false

    var body: some View {
        Form {
            Section("Keyboard & navigation") {
                NavigationLink {
                    KeyboardShortcutsHelpView()
                } label: {
                    Label("Keyboard shortcuts", systemImage: "keyboard")
                }
            }

            Section("Playback") {
                Picker("Default speed", selection: $defaultPlaybackSpeed) {
                    ForEach(PlaybackSpeed.allCases) { speed in
                        Text(speed.menuTitle).tag(speed.rawValue)
                    }
                }
                .onChange(of: defaultPlaybackSpeed) { _, rate in
                    PlaybackPreferences.savePlaybackRate(rate)
                }
                Picker("Default transcode quality", selection: $defaultVideoResolution) {
                    ForEach(PlaybackVideoResolution.allCases) { res in
                        Text(res.menuTitle).tag(res)
                    }
                }
                .onChange(of: defaultVideoResolution) { _, value in
                    PlaybackPreferences.saveVideoResolution(value)
                }
                Toggle("Prefer direct play on LAN", isOn: $preferDirectPlayLAN)
                    .onChange(of: preferDirectPlayLAN) { _, value in
                        PlaybackPreferences.preferDirectPlayOnLAN = value
                    }
                Toggle("Prefer HLS transcode (experimental)", isOn: $preferHLS)
                    .onChange(of: preferHLS) { _, value in
                        PlaybackPreferences.preferHLSTranscode = value
                    }
            }

            Section("Downloads") {
                if let persistError = downloadManager.persistError {
                    Text(persistError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Download save error: \(persistError)")
                }
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
                LabeledContent("Storage used") {
                    Text(ByteCountFormatter.string(fromByteCount: downloadManager.totalDownloadBytes, countStyle: .file))
                }
                Button("Retry failed downloads") {
                    downloadManager.retryFailedDownloads()
                }
                Button("Remove all completed", role: .destructive) {
                    downloadManager.deleteAllCompleted()
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

            Section("Maintenance") {
                Button("Clear artwork cache") {
                    showClearArtworkConfirm = true
                }
                ShareLink(item: AppDiagnostics.exportText(registry: registry, downloadManager: downloadManager)) {
                    Label("Export diagnostics", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel("Export diagnostics")
            }

            Section("Legal & support") {
                NavigationLink {
                    LicensesView()
                } label: {
                    Label("Open source licenses", systemImage: "doc.text")
                }
                Link(destination: EclipsePlexLinks.privacyPolicy) {
                    Label("Privacy policy", systemImage: "hand.raised")
                }
                Link(destination: EclipsePlexLinks.support) {
                    Label("Support", systemImage: "questionmark.circle")
                }
                Text("Independent third-party Plex client. Not affiliated with Plex Inc.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("App", value: EclipsePlexBranding.productName)
                LabeledContent("Version", value: AppVersion.displayString)
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
        .confirmDestructive(
            title: "Clear artwork cache?",
            message: "Posters will reload from your servers on next browse.",
            confirmLabel: "Clear",
            isPresented: $showClearArtworkConfirm
        ) {
            PlexArtworkCache.clearAll()
        }
    }

}
