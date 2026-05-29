//
//  RootShellView.swift
//  EclipsePlexClient
//

import SwiftUI
#if os(iOS) || os(tvOS)
import UIKit
#endif

/// Root UI: sidebar + detail navigation shell across platforms.
struct RootShellView: View {
    private struct LibraryTransitionTarget: Equatable {
        let serverID: UUID
        let libraryID: String
        let title: String
    }

    @AppStorage("selectedPlexServerId") private var selectedServerIdString = ""
    @AppStorage("selectedPlexLibraryId") private var selectedLibraryIdString = ""

    @StateObject private var plexRegistry = PlexServerRegistry()
    @EnvironmentObject private var focusCoordinator: KeyboardFocusCoordinator
    @EnvironmentObject private var downloadManager: OfflineDownloadManager
    @EnvironmentObject private var bootstrapController: AppBootstrapController
    @EnvironmentObject private var playbackPresenter: PlaybackPresenter

    @State private var showAddPlexServer = false
    @State private var showSettings = false
    @State private var showServerSearch = false
    @State private var didOfferAddServerOnLaunch = false
    @State private var serverToEdit: PlexServer?
    @State private var connectionPickerServer: PlexServer?
    @State private var serverManagementServer: PlexServer?
    @State private var catalogPath = NavigationPath()
    @State private var detailLoadingMessage: String?
    /// Set synchronously on library tap so the sidebar can show a spinner before
    /// the detail column finishes switching (especially on iPhone where the
    /// browse overlay covers the detail loading banner for ~250 ms).
    @State private var pendingLibraryID: String?
    @State private var libraryTransitionTarget: LibraryTransitionTarget?
    @State private var libraryTransitionError: String?
    @State private var detailLoadingTimeoutTask: Task<Void, Never>?
    @State private var detailLoadingCompleteTask: Task<Void, Never>?
    /// Coalesces library-list / selection mutations off the current render pass.
    @State private var librarySidebarSyncGeneration: UInt = 0

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

#if os(iOS) || os(tvOS)
    @State private var browseSheetPresented = false
    @State private var didPromptBrowseOnLaunch = false
#endif

#if os(iOS) || os(macOS) || os(tvOS)
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
#endif

    private var plexServers: [PlexServer] { plexRegistry.allServers }
    private var deviceServers: [PlexServer] { [PlexServer.downloads] }

#if os(iOS) || os(tvOS)
    /// Leading overlay menu (iPhone / compact iPad / Apple TV).
    private var usesBrowseOverlay: Bool {
        #if os(tvOS)
        true
        #else
        UIDevice.current.userInterfaceIdiom == .phone || horizontalSizeClass == .compact
        #endif
    }
#endif

    private var selectedPlexServer: PlexServer? {
        guard let uuid = selectedServerID else { return nil }
        if uuid == PlexServer.downloadsServerID { return PlexServer.downloads }
        return plexServers.first { $0.id == uuid }
    }

    private var librariesForSelectedServer: [PlexLibrary] {
        guard let server = selectedPlexServer else { return [] }
        if server.isDownloadsServer {
            return OfflineDownloadsLibrary.libraries(for: server.id)
        }
        if server.usesLivePlexAPI {
            return plexRegistry.librariesByServerID[server.id] ?? []
        }
        #if DEBUG
        // Only built-in fixture servers use offline sample sections. User-added
        // servers without a token/URL should show an empty list (and load error),
        // not fake "Movies / TV Shows / Music" that look like a real library list.
        if PlexSampleData.servers.contains(where: { $0.id == server.id }) {
            return PlexSampleData.libraries(for: server.id)
        }
        return []
        #else
        return []
        #endif
    }

    private var selectedPlexLibrary: PlexLibrary? {
        resolveSelectedLibrary(migrateStoredID: false)
    }

    private var isLibraryTransitioning: Bool {
        guard let target = libraryTransitionTarget else { return false }
        guard target.serverID == selectedServerID else { return false }
        return selectedPlexLibrary?.id != target.libraryID
    }

    private var syncStatusText: String {
        if plexRegistry.librariesLoadingServerID != nil {
            return "Syncing"
        }
        let pending = OfflineScrobbleQueue.diagnosticsSummary().pending
        if pending > 0 {
            return "Retrying"
        }
        return "Up to date"
    }

    private var selectedServerID: UUID? {
        UUID(uuidString: selectedServerIdString)
    }

    private func setSelectedServerID(_ id: UUID?) {
        selectedServerIdString = id?.uuidString ?? ""
    }

    private var selectedLibraryIDBinding: Binding<String?> {
        Binding(
            get: {
                selectedLibraryIdString.isEmpty ? nil : selectedLibraryIdString
            },
            set: { newValue in
                selectedLibraryIdString = newValue ?? ""
            }
        )
    }

    private var suppressBrowseShellForPlayback: Bool {
        playbackPresenter.hasActiveSession && playbackPresenter.presentationMode == .fullScreen
    }

    var body: some View {
        rootShell
            .browseShellSuppressedForPlayback(suppressBrowseShellForPlayback)
            .environmentObject(plexRegistry)
            .attachPlaybackPresenter(
                playbackPresenter,
                dependencies: PlaybackCoverDependencies(
                    downloadManager: downloadManager,
                    focusCoordinator: focusCoordinator,
                    plexRegistry: plexRegistry
                )
            )
            .task {
                await bootstrapController.markReady(minimumDuration: 0.25)
            }
            .task {
                await plexRegistry.refreshAllReachability()
            }
            .onChange(of: showSettings) { _, showing in
                focusCoordinator.browseKeyboardCommandsEnabled = !showing
            }
#if os(macOS)
            .onChange(of: suppressBrowseShellForPlayback) { _, suppressed in
                PlaybackWindowTitleController.shared.setSuppressed(suppressed)
            }
#endif
            .onChange(of: scenePhase) { _, phase in
                if phase == .background || phase == .inactive, playbackPresenter.hasActiveSession {
                    PlaybackNowPlayingController.shared.activateAudioSessionIfNeeded()
                }
                if phase == .active {
                    Task {
                        await plexRegistry.refreshAllReachability()
                    }
                    OfflineScrobbleQueue.scheduleFlush(servers: plexRegistry.allServers)
                    Task {
                        await downloadManager.pumpQueueIfAllowed()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eclipsePlexBrowseBack)) { _ in
                handleBrowseBack()
            }
            .onChange(of: selectedLibraryIdString) { _, _ in
                scheduleDetailFocusAdoption()
                scheduleLibraryNavigationCompletion()
            }
            .onChange(of: libraryNavigationReadyKey) { _, _ in
                scheduleLibraryNavigationCompletion()
            }
            .onChange(of: selectedServerIdString) { _, _ in
                scheduleDetailFocusAdoption()
            }
            .onChange(of: catalogPath.count) { _, _ in
                scheduleDetailFocusAdoption()
            }
            .environment(\.openBrowseMenu, OpenBrowseMenuAction(open: presentBrowseMenu))
            .environment(\.dismissBrowseMenu, DismissBrowseMenuAction(dismiss: dismissBrowseMenu))
            .modifier(
                RootShellNotificationHandlers(
                    plexRegistry: plexRegistry,
                    plexServers: plexServers,
                    connectionPickerServer: $connectionPickerServer,
                    refreshSelectedServerLibraries: refreshSelectedServerLibraries,
                    presentBrowseMenu: presentBrowseMenu,
                    presentServerSearch: presentServerSearch
                )
            )
            .environment(
                \.openServerSearch,
                OpenServerSearchAction(open: presentServerSearch)
            )
            .environment(
                \.catalogNavigationActions,
                CatalogNavigationActions(
                    selectLibrary: { library in
                        selectLibrary(library)
                    },
                    pushRoute: { route in
                        catalogPath.append(route)
                    },
                    popRoute: {
                        guard !catalogPath.isEmpty else { return }
                        catalogPath.removeLast()
                    }
                )
            )
            .sheet(isPresented: $showAddPlexServer) {
                AddPlexServerSheet(registry: plexRegistry) { added in
                    setSelectedServerID(added.id)
                    selectedLibraryIdString = ""
                    resetCatalogNavigation()
                    dismissBrowseMenu()
                }
            }
            .sheet(item: $serverToEdit) { server in
                EditPlexServerSheet(registry: plexRegistry, server: server)
            }
            .sheet(item: $connectionPickerServer) { server in
                ServerConnectionPickerSheet(server: server, registry: plexRegistry)
            }
            .sheet(item: $serverManagementServer) { server in
                ServerManagementView(registry: plexRegistry, server: server)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView(registry: plexRegistry)
                        .offlineDownloads(downloadManager)
                }
#if os(macOS)
                .frame(minWidth: 520, idealWidth: 560, minHeight: 420, idealHeight: 640)
#endif
            }
            .sheet(isPresented: $showServerSearch) {
                if let server = selectedPlexServer, server.usesLivePlexAPI {
                    ServerSearchView(
                        plexServer: server,
                        libraries: librariesForSelectedServer
                    )
                }
            }
            .onAppear {
#if os(macOS)
                MacAppDelegate.registry = plexRegistry
#endif
                downloadManager.configure(registry: plexRegistry)
                focusCoordinator.browseKeyboardCommandsEnabled = !showSettings
                applyUITestLaunchPresentationIfNeeded()
                // Empty selection = aggregate Home (all servers). Keep stored server id on upgrade.
                scheduleLibrarySidebarSync()
                adoptDetailKeyboardFocusIfNeeded()
                offerAddServerIfNeeded()
            }
            .task(id: selectedServerIdString) {
                if let server = selectedPlexServer, !server.isDownloadsServer {
                    plexRegistry.scheduleRefreshLibraries(for: server)
                } else if selectedServerID == nil {
                    plexRegistry.scheduleRefreshLibraries(for: plexServers)
                }
                scheduleLibrarySidebarSync()
            }
            .onChange(of: plexRegistry.librariesByServerID) { _, _ in
                scheduleLibrarySidebarSync()
            }
            .onChange(of: plexRegistry.librariesLoadingServerID) { _, _ in
                scheduleLibrarySidebarSync()
            }
    }

    @ViewBuilder
    private var rootShell: some View {
#if os(tvOS)
        phoneShell
#elseif os(iOS)
        if usesBrowseOverlay {
            phoneShell
        } else {
            ipadSplitShell
        }
#else
        splitShell
#endif
    }

#if os(iOS) || os(tvOS)
    private var phoneShell: some View {
        ZStack(alignment: .leading) {
            detailColumn

            if browseSheetPresented {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissBrowseMenu()
                    }
                    .transition(.opacity)
                    .zIndex(1)
            }
            browseOverlayPanel
                .offset(x: browseSheetPresented ? 0 : -min(320, UIScreen.main.bounds.width * 0.88))
                .opacity(browseSheetPresented ? 1 : 0.001)
                .allowsHitTesting(browseSheetPresented)
                .zIndex(2)

            // During library navigation the detail-column loading banner sits
            // underneath the browse sheet. Mirror it above the sheet so the
            // user gets immediate feedback that the tap registered.
            if pendingLibraryID != nil, let message = detailLoadingMessage {
                detailLoadingBanner(message: message)
                    .zIndex(3)
                    .transition(.opacity)
            }

            if !browseSheetPresented, !playbackPresenter.hasActiveSession {
                reopenMenuButton
                    .zIndex(4)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: browseSheetPresented)
    }

    private var browseOverlayPanel: some View {
        NavigationStack {
            browseSidebar()
        }
        .frame(width: min(320, UIScreen.main.bounds.width * 0.88))
        .frame(maxHeight: .infinity)
        .background(browseOverlayBackground)
        .shadow(color: .black.opacity(0.2), radius: 12, x: 4, y: 0)
    }

    private var browseOverlayBackground: Color {
        #if os(tvOS)
        Color(white: 0.12)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    private var reopenMenuButton: some View {
        VStack {
            HStack {
                Button(action: presentBrowseMenu) {
                    Image(systemName: "sidebar.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .disabled(playbackPresenter.hasActiveSession)
                .accessibilityIdentifier("browseMenuReopenOverlayButton")
                .padding(.leading, 12)
                .padding(.top, 8)
                Spacer()
            }
            Spacer()
        }
    }

    #if os(iOS)
    private var ipadSplitShell: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } detail: {
            detailColumn
        }
    }

    private func collapseSplitSidebar() {
#if os(iOS)
        guard horizontalSizeClass == .compact else { return }
#endif
        withAnimation(.easeInOut(duration: 0.25)) {
            columnVisibility = .detailOnly
        }
    }

    private func showSplitSidebar() {
        withAnimation(.easeInOut(duration: 0.25)) {
            columnVisibility = .all
        }
    }
    #endif
    #endif

#if os(macOS)
    private var splitShell: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } detail: {
            detailColumn
        }
    }
#endif

    private var sidebarColumn: some View {
        NavigationStack {
            browseSidebar()
        }
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        .detailColumnMacWindowTitlePolicy(suppressed: suppressBrowseShellForPlayback)
#endif
    }

    @ViewBuilder
    private func browseSidebar() -> some View {
        AppSidebarView(
            deviceServers: deviceServers,
            plexServers: plexServers,
            selectedServer: selectedPlexServer,
            libraries: librariesForSelectedServer,
            selectedServerID: Binding(
                get: { selectedServerID },
                set: { setSelectedServerID($0) }
            ),
            selectedLibraryID: selectedLibraryIDBinding,
            pendingLibraryID: pendingLibraryID,
            isLoadingLibraries: plexRegistry.librariesLoadingServerID == selectedPlexServer?.id,
            connectionIssueForServer: { plexRegistry.connectionIssue(for: $0) },
            isUserAddedServer: { plexRegistry.isUserAddedServer(id: $0) },
            serverReachable: { plexRegistry.serverReachable[$0] },
            serverLastOnlineAt: { plexRegistry.lastOnlineAt(for: $0) },
            onSelectServer: { selectServer($0) },
            onSelectHome: { selectHome() },
            onSelectPlaylists: { selectPlaylists() },
            onSelectLibrary: { selectLibrary($0) },
            onEditServer: { serverToEdit = $0 },
            onManageServer: { serverManagementServer = $0 },
            onRemoveServer: { id in
                guard id != PlexServer.downloadsServerID else { return }
                plexRegistry.removeCustomServer(id: id)
                if selectedServerID == id {
                    setSelectedServerID(plexServers.first?.id ?? PlexServer.downloadsServerID)
                    selectedLibraryIdString = ""
                    resetCatalogNavigation()
                }
            },
            onDismissSidebar: { dismissBrowseMenu() },
            activeDownloadCount: downloadManager.activeQueueCount,
            onSelectAllServersHome: { selectAllServersHome() },
            onSelectSettings: {
                showSettings = true
                dismissBrowseMenu()
            },
            onRetryLibraries: {
                guard let server = selectedPlexServer else { return }
                plexRegistry.scheduleRefreshLibraries(for: server, force: true)
            },
            onSignInToPlex: { showAddPlexServer = true },
            isAggregateHomeSelected: selectedServerID == nil,
            menuControlsDisabled: playbackPresenter.hasActiveSession
        )
    }

    private var detailColumn: some View {
        ZStack {
            NavigationStack(path: $catalogPath) {
                Group {
                    if let target = libraryTransitionTarget, isLibraryTransitioning {
                        libraryLoadingDetail(title: target.title)
                    } else if let server = selectedPlexServer, let library = selectedPlexLibrary {
                        Group {
                            if server.isDownloadsServer {
                                CatalogListView(
                                    plexServer: server,
                                    library: library,
                                    parent: .root,
                                    navigationTitle: library.title
                                )
                                .onAppear { focusCoordinator.focusCatalog() }
                            } else {
                                LibraryDetailView(plexServer: server, library: library)
                            }
                        }
                    } else if let server = selectedPlexServer, server.isDownloadsServer {
                        DownloadsHomeDetailView()
                    } else if let server = selectedPlexServer {
                        HomeDetailView(
                            plexServer: server,
                            libraries: librariesForSelectedServer,
                            connectionIssue: plexRegistry.connectionIssue(for: server),
                            onAddPlexServer: { showAddPlexServer = true },
                            onEditServer: { serverToEdit = server },
                            onRetryConnection: {
                                plexRegistry.scheduleRefreshLibraries(for: server, force: true)
                                Task { await plexRegistry.refreshReachability(for: server, force: true) }
                            },
                            onManageServer: { serverManagementServer = server },
                            onSignInToPlex: { showAddPlexServer = true }
                        )
                        .onAppear { adoptDetailKeyboardFocusIfNeeded() }
                    } else {
                        AggregateHomeDetailView(
                            plexServers: plexServers,
                            librariesByServerID: plexRegistry.librariesByServerID,
                            onAddPlexServer: { showAddPlexServer = true },
                            onSelectServer: { selectServer($0) }
                        )
                        .onAppear { adoptDetailKeyboardFocusIfNeeded() }
                    }
                }
                .navigationDestination(for: CatalogNavigationRoute.self) { route in
                    catalogDestination(for: route)
                }
            }
            .offlineDownloads(downloadManager)
            .toolbar { detailToolbar }
#if os(macOS)
            .detailColumnMacWindowTitlePolicy(suppressed: suppressBrowseShellForPlayback)
#endif

            if let message = detailLoadingMessage {
                detailLoadingBanner(message: message)
            }
        }
    }

    private func detailLoadingBanner(message: String) -> some View {
        VStack {
            HStack(spacing: 10) {
                fixedProgressIndicator(size: .regular)
                Text(message)
                    .font(.subheadline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding()
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    private func libraryLoadingDetail(title: String) -> some View {
        VStack(spacing: 14) {
            fixedProgressIndicator(size: .large)
            Text("Loading \(title)…")
                .font(.headline)
            Text("Preparing library content")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let libraryTransitionError {
                Text(libraryTransitionError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button("Retry", action: retryLibraryTransition)
                        .buttonStyle(.pressableBorderedProminent)
                    Button("Switch server", action: switchServerFromTransition)
                        .buttonStyle(.pressableBordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
    }

    private func retryLibraryTransition() {
        guard let target = libraryTransitionTarget else { return }
        libraryTransitionError = nil
        beginDetailLoading(message: "Loading \(target.title)…", persistUntilCleared: true)
        scheduleDetailLoadingTimeout()
        if let server = selectedPlexServer, !server.isDownloadsServer {
            plexRegistry.scheduleRefreshLibraries(for: server, force: true)
        } else {
            DispatchQueue.main.async {
                completeLibraryNavigationIfReady()
            }
        }
    }

    private func switchServerFromTransition() {
        libraryTransitionTarget = nil
        libraryTransitionError = nil
        selectedLibraryIdString = ""
        clearDetailLoading()
        focusCoordinator.focusSidebar()
        presentBrowseMenu()
    }

    // MARK: - Selection

    private func selectAllServersHome() {
        libraryTransitionTarget = nil
        libraryTransitionError = nil
        setSelectedServerID(nil)
        selectedLibraryIdString = ""
        resetCatalogNavigation()
        focusCoordinator.focusHome()
        dismissBrowseMenu()
        showDetailLoading(message: "Loading all servers…")
        plexRegistry.scheduleRefreshLibraries(for: plexServers)
    }

    private func selectServer(_ id: UUID) {
        guard selectedServerID != id else { return }
        libraryTransitionTarget = nil
        libraryTransitionError = nil
        AppPreferences.recordRecentServer(id: id)
        setSelectedServerID(id)
        selectedLibraryIdString = ""
        resetCatalogNavigation()
        showDetailLoading(message: "Loading server…")
        scheduleLibrarySidebarSync()
    }

    private func selectHome() {
        libraryTransitionTarget = nil
        libraryTransitionError = nil
        if selectedLibraryIdString.isEmpty {
            dismissBrowseMenu()
            return
        }
        selectedLibraryIdString = ""
        resetCatalogNavigation()
        focusCoordinator.focusHome()
        dismissBrowseMenu()
    }

    private func selectPlaylists() {
        libraryTransitionTarget = nil
        libraryTransitionError = nil
        selectedLibraryIdString = ""
        catalogPath = NavigationPath()
        catalogPath.append(CatalogNavigationRoute.serverPlaylists)
        dismissBrowseMenu()
    }

    private func selectLibrary(_ library: PlexLibrary) {
#if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
        guard let serverID = selectedServerID else { return }
        libraryTransitionTarget = LibraryTransitionTarget(
            serverID: serverID,
            libraryID: library.id,
            title: library.title
        )
        libraryTransitionError = nil
        // Mark pending immediately so the sidebar row shows a spinner on the
        // same frame as the tap — don't wait for the detail column to catch up.
        pendingLibraryID = library.id
        selectedLibraryIdString = library.id
        resetCatalogNavigation()
        focusCoordinator.focusCatalog()
        beginDetailLoading(message: "Loading \(library.title)…", persistUntilCleared: true)
        scheduleDetailLoadingTimeout()
        dismissBrowseMenu()
        // Defer completion check so SwiftUI can paint the pending spinner /
        // loading banner before any synchronous follow-up work on this frame.
        scheduleLibraryNavigationCompletion()
    }

    /// Short-lived banner for server/home transitions (auto-dismisses).
    private func showDetailLoading(message: String, duration: TimeInterval = 0.6) {
        beginDetailLoading(message: message, persistUntilCleared: false, autoDismissAfter: duration)
    }

    /// Starts or updates the detail loading banner. Library navigation keeps
    /// the banner visible until `completeLibraryNavigationIfReady()` clears it;
    /// other transitions auto-dismiss after `autoDismissAfter`.
    private func beginDetailLoading(
        message: String,
        persistUntilCleared: Bool,
        autoDismissAfter: TimeInterval = 0.6
    ) {
        detailLoadingCompleteTask?.cancel()
        detailLoadingMessage = message
        guard !persistUntilCleared else { return }
        detailLoadingCompleteTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(autoDismissAfter * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if detailLoadingMessage == message {
                detailLoadingMessage = nil
            }
        }
    }

    private func clearDetailLoading() {
        detailLoadingTimeoutTask?.cancel()
        detailLoadingCompleteTask?.cancel()
        detailLoadingTimeoutTask = nil
        detailLoadingCompleteTask = nil
        detailLoadingMessage = nil
        pendingLibraryID = nil
        if !isLibraryTransitioning {
            libraryTransitionTarget = nil
            libraryTransitionError = nil
        }
    }

    /// Safety valve so a stuck network fetch can't leave the banner up forever.
    private func scheduleDetailLoadingTimeout() {
        detailLoadingTimeoutTask?.cancel()
        detailLoadingTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            if isLibraryTransitioning {
                libraryTransitionError = "Still waiting for library data. You can retry or switch servers."
            } else {
                clearDetailLoading()
            }
        }
    }

    /// Clears the library navigation banner once the detail column is actually
    /// showing the requested library (or after a short minimum display time).
    private func completeLibraryNavigationIfReady() {
        guard pendingLibraryID != nil || detailLoadingMessage != nil else { return }
        guard let targetID = pendingLibraryID ?? (selectedLibraryIdString.isEmpty ? nil : selectedLibraryIdString),
              let resolved = selectedPlexLibrary,
              resolved.id == targetID
        else { return }

        if libraryTransitionTarget?.libraryID == targetID {
            libraryTransitionTarget = nil
            libraryTransitionError = nil
        }

        detailLoadingCompleteTask?.cancel()
        detailLoadingCompleteTask = Task { @MainActor in
            // Keep the banner visible briefly so taps feel acknowledged without
            // delaying the first library transition.
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            if selectedPlexLibrary?.id == targetID {
                clearDetailLoading()
            }
        }
    }

    /// Default keyboard focus for the detail column (home hubs vs catalog).
    private func adoptDetailKeyboardFocusIfNeeded() {
        guard catalogPath.isEmpty else { return }
        if selectedPlexServer?.isDownloadsServer == true, selectedPlexLibrary != nil {
            focusCoordinator.focusCatalog()
        } else if isHomeDetailVisible {
            focusCoordinator.focusHome()
        } else if focusCoordinator.route == .detailActions || focusCoordinator.route == .player {
            // After popping a `MediaDetailView` / `ShowDetailView`, the coordinator
            // can still be parked on `.detailActions` (set by the detail's onAppear).
            // The next navigation event would then flip the route a second time
            // in the same frame, firing the SwiftUI multi-update warning.
            // Snap back to the catalog pane when we land at the catalog root.
            if selectedPlexLibrary != nil {
                focusCoordinator.focusCatalog()
            } else {
                focusCoordinator.focusSidebar()
            }
        }
    }

    private var isHomeDetailVisible: Bool {
        catalogPath.isEmpty && selectedPlexLibrary == nil && selectedPlexServer?.isDownloadsServer != true
    }

    private func scheduleDetailFocusAdoption() {
        DispatchQueue.main.async {
            guard !isLibraryTransitioning else { return }
            adoptDetailKeyboardFocusIfNeeded()
        }
    }

    /// Changes when a sidebar library tap can resolve into `LibraryDetailView`.
    private var libraryNavigationReadyKey: String {
        let resolved = selectedPlexLibrary?.id ?? "nil"
        let count = librariesForSelectedServer.count
        return "\(selectedLibraryIdString)|\(resolved)|\(count)"
    }

    private func handleBrowseBack() {
        if !catalogPath.isEmpty {
            catalogPath.removeLast()
            adoptDetailKeyboardFocusIfNeeded()
            return
        }
        if focusCoordinator.route == .catalogList || focusCoordinator.route == .homeHubs {
            focusCoordinator.focusSidebar()
            return
        }
#if os(iOS) || os(tvOS)
        if usesBrowseOverlay, browseSheetPresented {
            dismissBrowseMenu()
        }
#endif
    }

    private func presentServerSearch() {
        guard let server = selectedPlexServer, server.usesLivePlexAPI else { return }
        showServerSearch = true
    }

    private func refreshSelectedServerLibraries() {
        if let server = selectedPlexServer, !server.isDownloadsServer {
            plexRegistry.scheduleRefreshLibraries(for: server)
        } else if selectedServerID == nil {
            plexRegistry.scheduleRefreshLibraries(for: plexServers)
        }
    }

    private func presentBrowseMenu() {
#if os(tvOS)
        withAnimation(.easeInOut(duration: 0.25)) {
            browseSheetPresented = true
        }
#elseif os(iOS)
        if usesBrowseOverlay {
            withAnimation(.easeInOut(duration: 0.25)) {
                browseSheetPresented = true
            }
        } else {
            showSplitSidebar()
        }
#else
        showSplitSidebar()
#endif
    }

    private func dismissBrowseMenu() {
#if os(tvOS)
        withAnimation(.easeInOut(duration: 0.25)) {
            browseSheetPresented = false
        }
#elseif os(iOS)
        if usesBrowseOverlay {
            withAnimation(.easeInOut(duration: 0.25)) {
                browseSheetPresented = false
            }
        } else {
            collapseSplitSidebar()
        }
#elseif os(macOS)
        withAnimation(.easeInOut(duration: 0.25)) {
            columnVisibility = .detailOnly
        }
#endif
    }

#if os(iOS) || os(tvOS)
    private func promptBrowseMenuIfNeeded() {}

#elseif os(macOS)
    private func showSplitSidebar() {
        withAnimation(.easeInOut(duration: 0.25)) {
            columnVisibility = .all
        }
    }
#endif

    private func offerAddServerIfNeeded() {
        guard !ProcessInfo.processInfo.arguments.contains("-UITestSkipOnboarding") else { return }
        guard !didOfferAddServerOnLaunch, plexServers.isEmpty else { return }
        didOfferAddServerOnLaunch = true
        DispatchQueue.main.async {
            showAddPlexServer = true
        }
    }

    private func resetCatalogNavigation() {
        catalogPath = NavigationPath()
    }

    @ViewBuilder
    private func catalogDestination(for route: CatalogNavigationRoute) -> some View {
        if let server = selectedPlexServer {
            Group {
                switch route {
                case .browse(let library, let parent, let navigationTitle):
                    CatalogListView(
                        plexServer: server,
                        library: library,
                        parent: parent,
                        navigationTitle: navigationTitle
                    )
                case .showDetail(let library, let show):
                    ShowDetailView(plexServer: server, library: library, show: show)
                case .media(let library, let node):
                    MediaDetailView(plexServer: server, library: library, node: node)
                case .serverPlaylists:
                    ServerPlaylistsView(plexServer: server)
                case .playlistItems(let playlistKey, let title):
                    PlaylistOrCollectionItemsView(
                        plexServer: server,
                        library: librariesForSelectedServer.first(where: { $0.sectionType == .movie })
                            ?? librariesForSelectedServer.first
                            ?? PlexLibrary(sectionKey: "1", title: "Library", type: 1),
                        parent: .playlist(ratingKey: playlistKey),
                        navigationTitle: title
                    )
                case .libraryCollections(let library):
                    LibraryCollectionsView(plexServer: server, library: library)
                case .collectionItems(let collectionKey, let title, let library):
                    PlaylistOrCollectionItemsView(
                        plexServer: server,
                        library: library,
                        parent: .collection(ratingKey: collectionKey),
                        navigationTitle: title
                    )
                case .liveTV:
                    LiveTVBrowseView(plexServer: server)
                case .pseudoTV:
                    PseudoTVChannelsView(plexServer: server, registry: plexRegistry)
                }
            }
            .offlineDownloads(downloadManager)
        } else {
            EmptyView()
        }
    }

    /// Runs library selection reconciliation on the next run-loop turn so
    /// NavigationStack / sidebar state does not update multiple times per frame.
    private func scheduleLibrarySidebarSync() {
        librarySidebarSyncGeneration &+= 1
        let generation = librarySidebarSyncGeneration
        DispatchQueue.main.async {
            guard generation == self.librarySidebarSyncGeneration else { return }
            self.performLibrarySidebarSync()
        }
    }

    private func scheduleLibraryNavigationCompletion() {
        DispatchQueue.main.async {
            self.completeLibraryNavigationIfReady()
        }
    }

    @MainActor
    private func performLibrarySidebarSync() {
        invalidateLibrarySelectionIfNeeded()
        guard !selectedLibraryIdString.isEmpty,
              selectedPlexLibrary == nil,
              let library = resolveSelectedLibrary(migrateStoredID: true)
        else {
            completeLibraryNavigationIfReady()
            return
        }
        selectedLibraryIdString = library.id
        resetCatalogNavigation()
    }

    private func invalidateLibrarySelectionIfNeeded() {
        let libs = librariesForSelectedServer
        guard !libs.isEmpty else {
            // If libraries are still loading for this server, keep the persisted
            // library selection so it can be restored once the fetch completes.
            if let server = selectedPlexServer,
               plexRegistry.librariesLoadingServerID == server.id {
                return
            }
            if selectedPlexServer?.isDownloadsServer != true {
                selectedLibraryIdString = ""
            }
            return
        }
        guard !selectedLibraryIdString.isEmpty else { return }
        if resolveSelectedLibrary(migrateStoredID: false) != nil { return }
        selectedLibraryIdString = ""
    }

    private func resolveSelectedLibrary(migrateStoredID: Bool) -> PlexLibrary? {
        guard !selectedLibraryIdString.isEmpty else { return nil }
        let libs = librariesForSelectedServer
        if let exact = libs.first(where: { $0.id == selectedLibraryIdString }) {
            return exact
        }
        guard let server = selectedPlexServer else { return nil }
        let prefix = "\(server.id.uuidString):"
        guard selectedLibraryIdString.hasPrefix(prefix) else { return nil }
        let legacyKey = String(selectedLibraryIdString.dropFirst(prefix.count))
        let normalized = PlexLibrary.normalizeSectionKey(legacyKey)
        guard let match = libs.first(where: { $0.sectionID == normalized }) else { return nil }
        if migrateStoredID {
            selectedLibraryIdString = match.id
        }
        return match
    }

    private func applyUITestLaunchPresentationIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
#if os(macOS)
        if args.contains("-UITestShowSidebar") {
            columnVisibility = .all
        }
#endif
#if os(iOS) || os(tvOS)
        if args.contains("-UITestShowSidebar") {
            browseSheetPresented = true
        }
#endif
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        #if os(iOS) || os(tvOS)
        ToolbarItem(placement: .topBarLeading) {
            Button(action: presentBrowseMenu) {
                Label("Browse", systemImage: "sidebar.left")
            }
            .disabled(playbackPresenter.hasActiveSession)
            .accessibilityIdentifier("browseMenuButton")
        }
        #endif

        if catalogPath.isEmpty,
           let server = selectedPlexServer,
           server.usesLivePlexAPI,
           !server.isDownloadsServer {
            ToolbarItem(placement: .automatic) {
                Button {
                    presentServerSearch()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("serverSearchButton")
            }
        }

        if catalogPath.isEmpty,
           let server = selectedPlexServer,
           server.usesLivePlexAPI,
           selectedPlexLibrary == nil {
            ToolbarItem(placement: .automatic) {
                Button {
                    plexRegistry.scheduleRefreshLibraries(for: server, force: true)
                } label: {
                    Label("Refresh Libraries", systemImage: "arrow.clockwise")
                }
                .disabled(plexRegistry.librariesLoadingServerID == server.id)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    serverManagementServer = server
                } label: {
                    Label("Server management", systemImage: "server.rack")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddPlexServer = true
                } label: {
                    Label("Add Plex Server", systemImage: "plus")
                }
            }
        }

        ToolbarItem(placement: .automatic) {
            Text(syncStatusText)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
        }
    }
}

#Preview {
    RootShellView()
        .offlineDownloads(OfflineDownloadManager())
}
