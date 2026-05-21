//
//  RootShellView.swift
//  EclipsePlexClient
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Root UI: collapsible browse menu + detail (catalog). iPhone uses a sheet; iPad/Mac use split view.
struct RootShellView: View {
    @AppStorage("selectedPlexServerId") private var selectedServerIdString = ""
    @AppStorage("selectedPlexLibraryId") private var selectedLibraryIdString = ""

    @StateObject private var plexRegistry = PlexServerRegistry()
    @EnvironmentObject private var downloadManager: OfflineDownloadManager

    @State private var showAddPlexServer = false
    @State private var showSettings = false
    @State private var didOfferAddServerOnLaunch = false
    @State private var serverToEdit: PlexServer?
    @State private var catalogPath = NavigationPath()

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

#if os(iOS)
    @State private var browseSheetPresented = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var didPromptBrowseOnLaunch = false
#elseif os(macOS)
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
#endif

    private var plexServers: [PlexServer] { plexRegistry.allServers }
    private var deviceServers: [PlexServer] { [PlexServer.downloads] }

#if os(iOS)
    /// Sheet when split-view sidebar is unreliable (iPhone, iPad compact / Slide Over).
    private var usesBrowseSheet: Bool {
        UIDevice.current.userInterfaceIdiom == .phone || horizontalSizeClass == .compact
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
            .environment(\.openBrowseMenu, OpenBrowseMenuAction(open: presentBrowseMenu))
            .environment(\.dismissBrowseMenu, DismissBrowseMenuAction(dismiss: dismissBrowseMenu))
            .onReceive(NotificationCenter.default.publisher(for: .eclipsePlexOpenBrowseMenu)) { _ in
                presentBrowseMenu()
            }
            .environment(
                \.catalogNavigationActions,
                CatalogNavigationActions(
                    selectLibrary: { library in
                        selectLibrary(library)
                    },
                    pushRoute: { route in
                        catalogPath.append(route)
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
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView(registry: plexRegistry)
                        .environmentObject(downloadManager)
                }
            }
            .onAppear {
                downloadManager.configure(registry: plexRegistry)
                // Empty selection = aggregate Home (all servers). Keep stored server id on upgrade.
                invalidateLibrarySelectionIfNeeded()
                offerAddServerIfNeeded()
#if os(iOS)
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
#if os(iOS)
            .sheet(isPresented: $browseSheetPresented) {
                NavigationStack {
                    browseSidebar()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: showAddPlexServer) { wasShowing, isShowing in
                if wasShowing, !isShowing {
                    promptBrowseMenuIfNeeded()
                }
            }
#endif
    }

    @ViewBuilder
    private var rootShell: some View {
#if os(iOS)
        if usesBrowseSheet {
            phoneShell
        } else {
            ipadSplitShell
        }
#else
        splitShell
#endif
    }

#if os(iOS)
    private var phoneShell: some View {
        detailColumn
    }

    private var ipadSplitShell: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } detail: {
            detailColumn
        }
    }
#endif

    private var splitShell: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } detail: {
            detailColumn
        }
    }

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
            isAggregateHomeSelected: selectedServerID == nil
        )
    }

    private var detailColumn: some View {
        NavigationStack(path: $catalogPath) {
            Group {
                if let server = selectedPlexServer, let library = selectedPlexLibrary {
                    CatalogListView(
                        plexServer: server,
                        library: library,
                        parent: .root,
                        navigationTitle: library.title
                    )
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
                } else {
                    AggregateHomeDetailView(
                        plexServers: plexServers,
                        librariesByServerID: plexRegistry.librariesByServerID,
                        onAddPlexServer: { showAddPlexServer = true },
                        onSelectServer: { selectServer($0) }
                    )
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
    }

    // MARK: - Selection

    private func selectAllServersHome() {
        setSelectedServerID(nil)
        selectedLibraryIdString = ""
        resetCatalogNavigation()
        dismissBrowseMenu()
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
        invalidateLibrarySelectionIfNeeded()
    }

    private func selectHome() {
        if selectedLibraryIdString.isEmpty {
            dismissBrowseMenu()
            return
        }
        selectedLibraryIdString = ""
        resetCatalogNavigation()
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
        dismissBrowseMenu()
    }

    private func presentBrowseMenu() {
#if os(iOS)
        if usesBrowseSheet {
            browseSheetPresented = true
        } else {
            showSplitSidebar()
        }
#else
        showSplitSidebar()
#endif
    }

    private func dismissBrowseMenu() {
#if os(iOS)
        if usesBrowseSheet {
            browseSheetPresented = false
        } else {
            collapseSplitSidebar()
        }
#elseif os(macOS)
        withAnimation(.easeInOut(duration: 0.25)) {
            columnVisibility = .detailOnly
        }
#endif
    }

#if os(iOS)
    private func promptBrowseMenuIfNeeded() {
        guard usesBrowseSheet, !didPromptBrowseOnLaunch else { return }
        guard !showAddPlexServer else { return }
        didPromptBrowseOnLaunch = true
        if selectedPlexLibrary == nil {
            browseSheetPresented = true
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
#elseif os(macOS)
    private func showSplitSidebar() {
        withAnimation(.easeInOut(duration: 0.25)) {
            columnVisibility = .all
        }
    }
#endif

    private func offerAddServerIfNeeded() {
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
}

#Preview {
    RootShellView()
        .offlineDownloads(OfflineDownloadManager())
}
