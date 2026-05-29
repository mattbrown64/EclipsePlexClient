//
//  SettingsView.swift
//  EclipsePlexClient
//

import SwiftUI
#if os(iOS)
import UserNotifications
#endif

struct SettingsView: View {
    @ObservedObject var registry: PlexServerRegistry
    @EnvironmentObject private var downloadManager: OfflineDownloadManager

    @State private var defaultPlaybackSpeed: Float = PlaybackPreferences.loadPlaybackRate()
    @State private var downloadWifiOnly: Bool = OfflineDownloadPreferences.wifiOnly
    @State private var defaultDownloadQuality: PlaybackVideoResolution = OfflineDownloadPreferences.defaultQuality
    @State private var notificationsEnabled: Bool = OfflineDownloadPreferences.notificationsEnabled
    @State private var notifyOnSuccess: Bool = OfflineDownloadPreferences.notifyOnSuccess
    @State private var notifyOnFailure: Bool = OfflineDownloadPreferences.notifyOnFailure
#if os(iOS)
    @State private var downloadNotificationStatus: UNAuthorizationStatus = .notDetermined
#endif
    @State private var defaultVideoResolution: PlaybackVideoResolution = PlaybackPreferences.load().videoResolution
    @State private var preferDirectPlayLAN: Bool = PlaybackPreferences.preferDirectPlayOnLAN
    @State private var preferHLS: Bool = PlaybackPreferences.preferHLSTranscode

    @State private var showSignOutConfirm = false
    @State private var showAddServer = false
    @State private var showClearArtworkConfirm = false
    @AppStorage("appVisualTheme") private var visualThemeRaw = AppVisualTheme.eclipse.rawValue

    private var visualThemeBinding: Binding<AppVisualTheme> {
        Binding(
            get: { AppVisualTheme(rawValue: visualThemeRaw) ?? .eclipse },
            set: { visualThemeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Group {
#if os(macOS)
            ScrollView {
                settingsForm
            }
#else
            settingsForm
#endif
        }
        .navigationTitle("Settings")
#if os(iOS)
        .task {
            downloadNotificationStatus = await OfflineDownloadNotifications.authorizationStatus()
        }
#endif
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

    private var settingsForm: some View {
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
                Toggle("Always resume where I left off", isOn: Binding(
                    get: { PlaybackPreferences.alwaysResumeWhereLeftOff },
                    set: { PlaybackPreferences.alwaysResumeWhereLeftOff = $0 }
                ))
                Toggle("Always skip intros", isOn: Binding(
                    get: { PlaybackPreferences.alwaysSkipIntros },
                    set: { PlaybackPreferences.alwaysSkipIntros = $0 }
                ))
                TextField("Preferred subtitle language (e.g. en)", text: Binding(
                    get: { PlaybackPreferences.preferredSubtitleLanguage ?? "" },
                    set: { PlaybackPreferences.preferredSubtitleLanguage = $0.isEmpty ? nil : $0 }
                ))
                TextField("Preferred audio language (e.g. en)", text: Binding(
                    get: { PlaybackPreferences.preferredAudioLanguage ?? "" },
                    set: { PlaybackPreferences.preferredAudioLanguage = $0.isEmpty ? nil : $0 }
                ))
                Stepper(
                    "Subtitle size: \(Int(PlaybackPreferences.subtitleFontSize))pt",
                    value: Binding(
                        get: { PlaybackPreferences.subtitleFontSize },
                        set: { PlaybackPreferences.subtitleFontSize = $0 }
                    ),
                    in: 10 ... 36
                )
                Button("Reset per-show skip preferences") {
                    SkipIntroPreferences.resetAllShowPreferences()
                }
            }

#if os(macOS)
            Section("macOS") {
                Toggle("Quit when closing window", isOn: Binding(
                    get: { AppPreferences.quitWhenClosingWindow },
                    set: { AppPreferences.quitWhenClosingWindow = $0 }
                ))
            }
#endif

            Section("Theme") {
                Picker("Visual theme", selection: visualThemeBinding) {
                    ForEach(AppVisualTheme.allCases) { theme in
                        HStack(spacing: 10) {
                            AppThemeSwatch(theme: theme)
                            Text(theme.label)
                        }
                        .tag(theme)
                    }
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
#if os(iOS)
                Toggle("Download notifications", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, value in
                        OfflineDownloadPreferences.notificationsEnabled = value
                        if value {
                            Task {
                                _ = await OfflineDownloadNotifications.requestAuthorizationIfNeeded()
                                downloadNotificationStatus = await OfflineDownloadNotifications.authorizationStatus()
                            }
                        }
                    }
                Toggle("Notify on completion", isOn: $notifyOnSuccess)
                    .onChange(of: notifyOnSuccess) { _, value in
                        OfflineDownloadPreferences.notifyOnSuccess = value
                    }
                    .disabled(!notificationsEnabled)
                Toggle("Notify on failure", isOn: $notifyOnFailure)
                    .onChange(of: notifyOnFailure) { _, value in
                        OfflineDownloadPreferences.notifyOnFailure = value
                    }
                    .disabled(!notificationsEnabled)
                if downloadNotificationStatus == .denied {
                    Text("Notifications are denied for EclipsePlex. Enable notifications in iOS Settings to receive download alerts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
#endif
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
                        .offlineDownloads(downloadManager)
                } label: {
                    Label("Manage downloads", systemImage: "arrow.down.circle")
                }
            }

            SettingsServersSection(registry: registry)

            Section("Plex account") {
                Button("Add Plex Server…") {
                    showAddServer = true
                }
                if registry.plexAccountAuthToken != nil {
                    Button("Sign out of Plex.tv", role: .destructive) {
                        showSignOutConfirm = true
                    }
                }
                Text("Plex Home profile switching is documented in Docs/PlexHomeUsers.md. Managed-user tokens are not wired yet; libraries use each server’s main token.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Maintenance") {
                Button("Refresh all servers") {
                    Task {
                        await registry.refreshAllLibraries(force: true)
                        await AggregateHomeHubService.invalidateAll()
                    }
                }
                Button("Clear artwork cache") {
                    showClearArtworkConfirm = true
                }
#if os(tvOS)
                NavigationLink {
                    ScrollView {
                        Text(AppDiagnostics.exportText(registry: registry, downloadManager: downloadManager))
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle("Diagnostics")
                } label: {
                    Label("View diagnostics", systemImage: "doc.text.magnifyingglass")
                }
#else
                ShareLink(item: AppDiagnostics.exportText(registry: registry, downloadManager: downloadManager)) {
                    Label("Export diagnostics", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel("Export diagnostics")
#endif
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
#if os(macOS)
        .formStyle(.grouped)
        .scrollDisabled(true)
#endif
    }

}
