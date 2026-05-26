//
//  RootShellView.swift
//  EclipsePlexClient
//

import SwiftUI
#if os(iOS) || os(tvOS)
import UIKit
#endif

/// Root UI: collapsible browse menu + detail (catalog). iPhone uses a leading overlay; iPad/Mac use split view.
struct RootShellView: View {
    @AppStorage("selectedPlexServerId") private var selectedServerIdString = ""
    @AppStorage("selectedPlexLibraryId") private var selectedLibraryIdString = ""

    @StateObject private var plexRegistry = PlexServerRegistry()
    @EnvironmentObject private var focusCoordinator: KeyboardFocusCoordinator
    @EnvironmentObject private var downloadManager: OfflineDownloadManager
    @EnvironmentObject private var bootstrapController: AppBootstrapController

    @State private var showAddPlexServer = false
    @State private var showSettings = false
    @State private var showServerSearch = false
    @State private var didOfferAddServerOnLaunch = false
    @State private var serverToEdit: PlexServer?
    @State private var connectionPickerServer: PlexServer?
    @State private var catalogPath = NavigationPath()
    @State private var detailLoadingMessage: String?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

#if os(iOS) || os(tvOS)
    @State private var browseSheetPresented = false
    @State private var didPromptBrowseOnLaunch = false
#endif
#if os(iOS) || os(macOS)
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
        return PlexSampleData.libraries(for: server.id)
        #else
        return []
        #endif
    }

    private var selectedPlexLibrary: PlexLibrary? {
        resolveSelectedLibrary(migrateStoredID: false)
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

    var body: some View {
        rootShell
            .environmentObject(plexRegistry)
            .task {
                await bootstrapController.markReady(minimumDuration: 0.25)
            }
            .task {
                await plexRegistry.refreshAllReachability()
            }
            .onChange(of: showSettings) { _, showing in
                focusCoordinator.browseKeyboardCommandsEnabled = !showing
            }
            .onReceive(NotificationCenter.default.publisher(for: .eclipsePlexBrowseBack)) { _ in
                handleBrowseBack()
            }
            .onChange(of: selectedLibraryIdString) { _, _ in
                adoptDetailKeyboardFocusIfNeeded()
            }
            .onChange(of: selectedServerIdString) { _, _ in
                adoptDetailKeyboardFocusIfNeeded()
            }
            .onChange(of: catalogPath.count) { _, _ in
                adoptDetailKeyboardFocusIfNeeded()
            }
            .environment(\.openBrowseMenu, OpenBrowseMenuAction(open: presentBrowseMenu))
            .environment(\.dismissBrowseMenu, DismissBrowseMenuAction(dismiss: dismissBrowseMenu))
            .onReceive(NotificationCenter.default.publisher(for: .eclipsePlexOpenBrowseMenu)) { _ in
                presentBrowseMenu()
            }
            .onReceive(NotificationCenter.default.publisher(for: .eclipsePlexOpenSearch)) { _ in
                presentServerSearch()
            }
            .onReceive(NotificationCenter.default.publisher(for: .eclipsePlexRefreshLibraries)) { _ in
                Task { await refreshSelectedServerLibraries() }
            }
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
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView(registry: plexRegistry)
                        .environmentObject(downloadManager)
                }
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
                downloadManager.configure(registry: plexRegistry)
                focusCoordinator.browseKeyboardCommandsEnabled = !showSettings
                applyUITestLaunchPresentationIfNeeded()
                // Empty selection = aggregate Home (all servers). Keep stored server id on upgrade.
                invalidateLibrarySelectionIfNeeded()
                adoptDetailKeyboardFocusIfNeeded()
                offerAddServerIfNeeded()
#if os(iOS) || os(tvOS)
                promptBrowseMenuIfNeeded()
#endif
            }
            .task(id: selectedServerIdString) {
                if let server = selectedPlexServer, !server.isDownloadsServer {
                    await plexRegistry.refreshLibraries(for: server)
                } else if selectedServerID == nil {
                    await refreshLibrariesForAllPlexServers()
                }
                invalidateLibrarySelectionIfNeeded()
                applyPendingLibrarySelectionIfNeeded()
            }
            .onChange(of: plexRegistry.librariesByServerID) { _, _ in
                applyPendingLibrarySelectionIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        await OfflineScrobbleQueue.flush(servers: plexRegistry.allServers)
                        await downloadManager.pumpQueueIfAllowed()
                    }
                }
            }
#if os(iOS) || os(tvOS)
            .onChange(of: showAddPlexServer) { wasShowing, isShowing in
                if wasShowing, !isShowing {
                    promptBrowseMenuIfNeeded()
                }
            }
#endif
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

                browseOverlayPanel
                    .transition(.move(edge: .leading))
                    .zIndex(2)
            }
        }
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

    #if os(iOS)
    private var ipadSplitShell: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } detail: {
            detailColumn
        }
    }

    private func collapseSplitSidebar() {
        guard horizontalSizeClass == .compact else { return }
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
            isLoadingLibraries: plexRegistry.librariesLoadingServerID == selectedPlexServer?.id,
            librariesLoadError: plexRegistry.librariesLoadError,
            showsLibrariesError: plexRegistry.librariesLoadErrorServerID == selectedPlexServer?.id,
            isUserAddedServer: { plexRegistry.isUserAddedServer(id: $0) },
            serverReachable: { plexRegistry.serverReachable[$0] },
            onSelectServer: { selectServer($0) },
            onSelectHome: { selectHome() },
            onSelectPlaylists: { selectPlaylists() },
            onSelectLibrary: { selectLibrary($0) },
            onEditServer: { serverToEdit = $0 },
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
                Task { await plexRegistry.refreshLibraries(for: server) }
            },
            isAggregateHomeSelected: selectedServerID == nil
        )
    }

    private var detailColumn: some View {
        ZStack {
            NavigationStack(path: $catalogPath) {
                Group {
                    if let server = selectedPlexServer, let library = selectedPlexLibrary {
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
                        .browseMenuToolbar()
                        .id("\(server.id.uuidString)|\(library.id)")
                    } else if let server = selectedPlexServer, server.isDownloadsServer {
                        DownloadsHomeDetailView()
                    } else if let server = selectedPlexServer {
                        HomeDetailView(
                            plexServer: server,
                            libraries: librariesForSelectedServer,
                            onAddPlexServer: { showAddPlexServer = true }
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
            .toolbar {
            ToolbarItem(placement: .automatic) {
                if let server = selectedPlexServer, server.usesLivePlexAPI {
                    Button {
                        presentServerSearch()
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .accessibilityIdentifier("serverSearchButton")
                }
            }
            ToolbarItem(placement: .automatic) {
                if let server = selectedPlexServer, server.usesLivePlexAPI {
                    Button {
                        Task { await plexRegistry.refreshLibraries(for: server) }
                    } label: {
                        Label("Refresh Libraries", systemImage: "arrow.clockwise")
                    }
                    .disabled(plexRegistry.librariesLoadingServerID == server.id)
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

            if let message = detailLoadingMessage {
                VStack {
                    HStack {
                        ProgressView()
                        Text(message)
                            .font(.subheadline)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding()
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Selection

    private func selectAllServersHome() {
        setSelectedServerID(nil)
        selectedLibraryIdString = ""
        resetCatalogNavigation()
        focusCoordinator.focusHome()
        dismissBrowseMenu()
        showDetailLoading(message: "Loading all servers…")
        Task { await refreshLibrariesForAllPlexServers() }
    }

    private func refreshLibrariesForAllPlexServers() async {
        for server in plexServers where server.usesLivePlexAPI {
            await plexRegistry.refreshLibraries(for: server)
        }
    }

    private func selectServer(_ id: UUID) {
        guard selectedServerID != id else { return }
        setSelectedServerID(id)
        selectedLibraryIdString = ""
        resetCatalogNavigation()
        showDetailLoading(message: "Loading server…")
        invalidateLibrarySelectionIfNeeded()
    }

    private func selectHome() {
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
        selectedLibraryIdString = ""
        catalogPath = NavigationPath()
        catalogPath.append(CatalogNavigationRoute.serverPlaylists)
        dismissBrowseMenu()
    }

    private func selectLibrary(_ library: PlexLibrary) {
        selectedLibraryIdString = library.id
        resetCatalogNavigation()
        focusCoordinator.focusCatalog()
        dismissBrowseMenu()
        showDetailLoading(message: "Loading \(library.title)…")
    }

    private func showDetailLoading(message: String, duration: TimeInterval = 0.35) {
        detailLoadingMessage = message
        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await MainActor.run {
                if detailLoadingMessage == message {
                    detailLoadingMessage = nil
                }
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
        }
    }

    private var isHomeDetailVisible: Bool {
        catalogPath.isEmpty && selectedPlexLibrary == nil && selectedPlexServer?.isDownloadsServer != true
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

    private func refreshSelectedServerLibraries() async {
        if let server = selectedPlexServer, !server.isDownloadsServer {
            await plexRegistry.refreshLibraries(for: server)
        } else if selectedServerID == nil {
            await refreshLibrariesForAllPlexServers()
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
    private func promptBrowseMenuIfNeeded() {
        #if os(tvOS)
        guard !didPromptBrowseOnLaunch else { return }
        #else
        guard usesBrowseOverlay, !didPromptBrowseOnLaunch else { return }
        #endif
        guard !showAddPlexServer else { return }
        didPromptBrowseOnLaunch = true
        if selectedPlexLibrary == nil {
            withAnimation(.easeInOut(duration: 0.25)) {
                browseSheetPresented = true
            }
        }
    }

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
                }
            }
            .offlineDownloads(downloadManager)
        } else {
            EmptyView()
        }
    }

    private func applyPendingLibrarySelectionIfNeeded() {
        guard !selectedLibraryIdString.isEmpty,
              selectedPlexLibrary == nil,
              let library = resolveSelectedLibrary(migrateStoredID: true)
        else { return }
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
        if selectedLibraryIdString.isEmpty { return }
        _ = resolveSelectedLibrary(migrateStoredID: true)
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
}

#Preview {
    RootShellView()
        .offlineDownloads(OfflineDownloadManager())
}
