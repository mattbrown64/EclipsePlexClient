//
//  CatalogListView.swift
//  EclipsePlexClient
//
//  Created by Matt Brown on 5/15/26.
//

import SwiftUI

private enum CatalogSort: String, CaseIterable, Identifiable {
    case plexDefault = "default"
    case titleAscending = "title_asc"
    case titleDescending = "title_desc"
    case yearDescending = "year_desc"
    case yearAscending = "year_asc"
    case dateAddedDescending = "added_desc"
    case dateAddedAscending = "added_asc"
    case releaseDateDescending = "release_desc"
    case releaseDateAscending = "release_asc"
    case seasonEpisode = "season_episode"

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .plexDefault: "Default (Plex)"
        case .titleAscending: "Title (A–Z)"
        case .titleDescending: "Title (Z–A)"
        case .yearDescending: "Year (newest)"
        case .yearAscending: "Year (oldest)"
        case .dateAddedDescending: "Date added (newest)"
        case .dateAddedAscending: "Date added (oldest)"
        case .releaseDateDescending: "Release date (newest)"
        case .releaseDateAscending: "Release date (oldest)"
        case .seasonEpisode: "Season & episode"
        }
    }

    /// Shown in the toolbar when this sort is active.
    var shortTitle: String {
        switch self {
        case .plexDefault: "Default"
        default: menuTitle
        }
    }
}

/// Browses catalog rows for one `PlexLibrary` via the live Plex Media Server API.
struct CatalogListView: View {
    let plexServer: PlexServer
    let library: PlexLibrary
    let parent: PlexCatalogParent
    let navigationTitle: String
    /// Embedded in [`LibraryDetailView`](LibraryDetailView.swift) Browse tab (suppress duplicate chrome).
    var embedInLibraryShell: Bool = false

    @State private var searchText = ""
    @State private var sortOrder: CatalogSort = .plexDefault
    @State private var watchFilter: CatalogWatchFilter = .all
    @State private var viewMode: CatalogViewMode = .grid
    @State private var liveLoadedNodes: [PlexCatalogNode]?
    @State private var liveLoadError: String?
    @State private var catalogHasMore = false
    @State private var catalogNextOffset = 0
    @State private var isLoadingMore = false
    @State private var listFilters = CatalogListFilters()
    @State private var availableGenres: [PlexLibraryGenre] = []
    @State private var pendingDeleteShowGroupKey: String?
    @State private var showDeleteShowConfirm = false
    /// Cached output of filter + sort. Recomputing on every `body` pass was an
    /// O(n log n) hit per keystroke / focus change for large libraries.
    @State private var displayedNodes: [PlexCatalogNode] = []
    /// Pre-indexed mirror of `displayedNodes`. ForEach previously wrapped
    /// `displayedNodes.enumerated()` in `Array(...)` on every render — that
    /// allocated a fresh `[(Int, PlexCatalogNode)]` per body pass. Caching the
    /// indexed view as @State eliminates that and preserves identity-based
    /// row diffing via `.id` on `IndexedCatalogNode`.
    @State private var indexedDisplayedNodes: [IndexedCatalogNode] = []
    /// Identity of the last reload so changing a filter doesn't wipe the screen
    /// while refetching — only server/library/parent transitions blank the UI.
    @State private var lastReloadIdentity: String = ""
    /// Debounce handle for search keystrokes; coalesces focus + filter work.
    @State private var searchDebounceTask: Task<Void, Never>?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.catalogNavigationActions) private var catalogNavigationActions
    @EnvironmentObject private var downloadManager: OfflineDownloadManager
    @EnvironmentObject private var focusCoordinator: KeyboardFocusCoordinator
    @EnvironmentObject private var plexRegistry: PlexServerRegistry

    @State private var catalogGridColumnCount: Int = 5

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var catalogNodes: [PlexCatalogNode] {
        liveLoadedNodes ?? []
    }

    private var filteredNodes: [PlexCatalogNode] {
        let q = trimmedSearch
        let base = catalogNodes
        guard !q.isEmpty else { return base }
        return base.filter { $0.matchesSearch(trimmedQuery: q) }
    }

    private var sortStorageKey: String {
        let parentKey: String
        switch parent {
        case .root: parentKey = "root"
        case .show(let k): parentKey = "show:\(k)"
        case .season(let k): parentKey = "season:\(k)"
        case .collection(let k): parentKey = "collection:\(k)"
        case .playlist(let k): parentKey = "playlist:\(k)"
        }
        return "catalogSort.v1.\(plexServer.id.uuidString).\(library.id).\(parentKey)"
    }

    private var watchFilterStorageKey: String {
        let parentKey: String
        switch parent {
        case .root: parentKey = "root"
        case .show(let k): parentKey = "show:\(k)"
        case .season(let k): parentKey = "season:\(k)"
        case .collection(let k): parentKey = "collection:\(k)"
        case .playlist(let k): parentKey = "playlist:\(k)"
        }
        return "catalogWatchFilter.v1.\(plexServer.id.uuidString).\(library.id).\(parentKey)"
    }

    /// Recomputes `displayedNodes` from current inputs. Cheap to call on
    /// `onChange`, never on `body`.
    private func recomputeDisplayedNodes() {
        let filtered = filteredNodes
        let sorted = Self.sortedNodes(filtered, by: sortOrder)
        displayedNodes = sorted
        indexedDisplayedNodes = sorted.enumerated().map { IndexedCatalogNode(index: $0.offset, node: $0.element) }
        syncCatalogFocusState()
    }

    private var catalogFocusRegistrationID: String {
        let parentKey: String
        switch parent {
        case .root: parentKey = "root"
        case .show(let k): parentKey = "show:\(k)"
        case .season(let k): parentKey = "season:\(k)"
        case .collection(let k): parentKey = "collection:\(k)"
        case .playlist(let k): parentKey = "playlist:\(k)"
        }
        return "\(plexServer.id.uuidString)|\(library.id)|\(parentKey)"
    }

    private var loadTaskKey: String {
        let parentKey: String
        switch parent {
        case .root: parentKey = "root"
        case .show(let k): parentKey = "show:\(k)"
        case .season(let k): parentKey = "season:\(k)"
        case .collection(let k): parentKey = "collection:\(k)"
        case .playlist(let k): parentKey = "playlist:\(k)"
        }
        if plexServer.isDownloadsServer {
            // Use the *structural* revision, not `catalogRevision`. Otherwise
            // every throttled persist tick during an active download
            // cancels and restarts this view's `.task(id:)` loader — that
            // restart churn was a navigation-crash amplifier (stale `.task`
            // continuations completing on a torn-down view).
            return "offline|\(library.id)|\(parentKey)|\(downloadManager.catalogStructureRevision)"
        }
        let filterKey = "\(listFilters.genreFilterKey ?? "")|\(listFilters.year.map(String.init) ?? "")"
        // `plexServer.usesLivePlexAPI` is intentionally omitted: it can flip
        // mid-navigation during a background reachability refresh, which used
        // to cancel and restart `reloadCatalog()` and blank the visible
        // catalog. `reloadCatalog()` already reads the live value when it
        // runs, so the key only needs to encode the *user-selected* shape.
        return "\(plexServer.id.uuidString)|\(library.id)|\(parentKey)|\(watchFilter.rawValue)|\(filterKey)"
    }

    /// Identity key — changes only when the screen is showing a fundamentally
    /// different data set (server/library/parent). Filter/search/sort changes
    /// do NOT change this, so they refetch without blanking the UI.
    private var reloadIdentityKey: String {
        let parentKey: String
        switch parent {
        case .root: parentKey = "root"
        case .show(let k): parentKey = "show:\(k)"
        case .season(let k): parentKey = "season:\(k)"
        case .collection(let k): parentKey = "collection:\(k)"
        case .playlist(let k): parentKey = "playlist:\(k)"
        }
        return "\(plexServer.id.uuidString)|\(library.id)|\(parentKey)|\(plexServer.usesLivePlexAPI)"
    }

    private var listFiltersStorageKey: String {
        "catalogListFilters.v1.\(plexServer.id.uuidString).\(library.id)"
    }

    private var supportsLibraryFilters: Bool {
        plexServer.usesLivePlexAPI
            && !plexServer.isDownloadsServer
            && parent == .root
            && (library.sectionType == .movie || library.sectionType == .show)
    }

    private var supportsPagedCatalog: Bool {
        plexServer.usesLivePlexAPI
            && !plexServer.isDownloadsServer
            && parent == .root
            && (library.sectionType == .movie || library.sectionType == .show || library.sectionType == .photo)
    }

    private var isPhotoLibrary: Bool {
        library.sectionType == .photo && parent == .root
    }

    @State private var photoSlideshowStartIndex: Int?
    @State private var showPhotoSlideshow = false

    private var showsCollectionsLink: Bool {
        !embedInLibraryShell
            && plexServer.usesLivePlexAPI
            && !plexServer.isDownloadsServer
            && parent == .root
            && (library.sectionType == .movie || library.sectionType == .show)
    }

    private var yearFilterOptions: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return (1920 ... current).reversed()
    }

    var body: some View {
        applyFocusTracking(to: applyCatalogChrome(to: catalogStateContent))
    }

    @ViewBuilder
    private var catalogStateContent: some View {
        if !plexServer.usesLivePlexAPI, !plexServer.isDownloadsServer {
            #if DEBUG
            debugFixtureListContent
            #else
            ContentUnavailableView {
                Label("Server not configured", systemImage: "server.rack")
            } description: {
                Text("Add a reachable Plex URL and token to browse this library.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
        } else if liveLoadedNodes == nil, liveLoadError == nil {
            ProgressView("Loading catalog…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let liveLoadError {
            ContentUnavailableView {
                Label("Couldn’t load library", systemImage: "exclamationmark.triangle")
            } description: {
                Text(liveLoadError)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if displayedNodes.isEmpty {
            catalogEmptyState
        } else {
            listContent
        }
    }

    private var catalogEmptyState: some View {
        ContentUnavailableView {
            Label("Nothing here", systemImage: "film.stack")
        } description: {
            if watchFilter != .all {
                Text("No \(watchFilter.menuTitle.lowercased()) items in this list. Try changing the watch filter.")
            } else if !trimmedSearch.isEmpty {
                Text("No titles match your search.")
            } else if listFilters.isActive {
                Text("No titles match the selected genre or year. Try clearing filters.")
            } else if plexServer.isDownloadsServer {
                Text("Download movies or episodes from a Plex server to see them here.")
            } else {
                Text("This library section is empty.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func applyCatalogChrome<Content: View>(to content: Content) -> some View {
        Group {
            if embedInLibraryShell {
                content
            } else {
                content
                    .navigationTitle(navigationTitle)
#if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
#endif
            }
        }
            .searchable(text: $searchText, prompt: Text("Search this list"))
            .toolbar { catalogToolbarContent }
            .refreshable { await reloadCatalog() }
            .task(id: loadTaskKey) { await reloadCatalog() }
            .task(id: "\(plexServer.id)|adminCapabilities") {
                await MediaMetadataAdminAccess.refreshCapabilitiesIfNeeded(
                    plexServer: plexServer,
                    registry: plexRegistry
                )
            }
            .onAppear {
                loadSavedSortOrder()
                loadSavedWatchFilter()
                loadSavedListFilters()
                loadSavedViewMode()
            }
            .onChange(of: viewMode) { _, mode in
                saveViewMode(mode)
                syncCatalogFocusState()
            }
            .confirmDestructive(
                title: deleteShowConfirmTitle,
                message: deleteShowConfirmMessage,
                confirmLabel: "Delete",
                isPresented: $showDeleteShowConfirm,
                onConfirm: confirmDeleteShow
            )
            .task(id: "\(library.id)|genres") { await loadGenreFiltersIfNeeded() }
            .onChange(of: sortOrder) { _, newValue in
                UserDefaults.standard.set(newValue.rawValue, forKey: sortStorageKey)
            }
            .onChange(of: watchFilter) { _, newValue in
                UserDefaults.standard.set(newValue.rawValue, forKey: watchFilterStorageKey)
            }
            .onChange(of: listFilters) { _, newValue in
                saveListFilters(newValue)
            }
            .modifier(PhotoSlideshowPresentation(
                isPresented: $showPhotoSlideshow,
                plexServer: plexServer,
                photos: displayedNodes,
                startIndex: photoSlideshowStartIndex ?? 0
            ))
    }

    @ToolbarContentBuilder
    private var catalogToolbarContent: some ToolbarContent {
#if os(iOS)
        if horizontalSizeClass == .compact {
            ToolbarItem(placement: .topBarTrailing) {
                catalogOptionsMenu
            }
        } else {
            catalogExpandedToolbarItems
        }
#else
        catalogExpandedToolbarItems
#endif
    }

    private func confirmDeleteShow() {
        if let key = pendingDeleteShowGroupKey {
            downloadManager.deleteShow(groupKey: key)
            if isBrowsingDownloadedShowEpisodes {
                catalogNavigationActions.popRoute()
            }
        }
        pendingDeleteShowGroupKey = nil
    }

    private func applyFocusTracking<Content: View>(to content: Content) -> some View {
        content
            .onAppear {
                focusCoordinator.clearHomeItems()
                syncCatalogFocusState()
            }
            .onDisappear {
                focusCoordinator.unregisterCatalogActivateHandler(id: catalogFocusRegistrationID)
                searchDebounceTask?.cancel()
                searchDebounceTask = nil
            }
            .onChange(of: focusCoordinator.catalogActivateRequestID) { _, _ in
                guard focusCoordinator.catalogActivateHandlerOwnerID == catalogFocusRegistrationID else { return }
                openFocusedCatalogItem()
            }
            .onChange(of: sortOrder) { _, _ in recomputeDisplayedNodes() }
            .onChange(of: searchText) { _, _ in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard !Task.isCancelled else { return }
                    recomputeDisplayedNodes()
                }
            }
            .onChange(of: catalogGridColumnCount) { _, _ in syncCatalogFocusState() }
            .onChange(of: viewMode) { _, _ in syncCatalogFocusState() }
    }

    private func syncCatalogFocusState() {
        let nodes = displayedNodes
        let isGrid = viewMode == .grid
        focusCoordinator.updateCatalogLayout(
            itemCount: nodes.count,
            isGrid: isGrid,
            columnCount: isGrid ? max(catalogGridColumnCount, 2) : 1,
            handlerID: catalogFocusRegistrationID
        )
    }

    private func openFocusedCatalogItem() {
        let nodes = displayedNodes
        let index = focusCoordinator.catalogFocusedIndex
        guard nodes.indices.contains(index) else { return }
        catalogNavigationActions.pushRoute(catalogRoute(for: nodes[index]))
    }

    /// Offline TV: group key when this screen lists episodes for one show.
    private var downloadsShowGroupKey: String? {
        guard plexServer.isDownloadsServer else { return nil }
        if case .show(let showKey) = parent {
            return OfflineDownloadCatalog.showGroupKey(fromCatalogRatingKey: showKey)
        }
        return nil
    }

    private var isBrowsingDownloadedShowEpisodes: Bool {
        downloadsShowGroupKey != nil
    }

    private var deleteShowConfirmTitle: String {
        "Delete show?"
    }

    private var deleteShowConfirmMessage: String {
        let name = navigationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return "Removes all downloaded episodes for this show from this device."
        }
        return "Removes all downloaded episodes for “\(name)” from this device."
    }

    private func requestDeleteShow(groupKey: String) {
        pendingDeleteShowGroupKey = groupKey
        showDeleteShowConfirm = true
    }

    @ToolbarContentBuilder
    private var catalogExpandedToolbarItems: some ToolbarContent {
        if let groupKey = downloadsShowGroupKey {
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete show", role: .destructive) {
                    requestDeleteShow(groupKey: groupKey)
                }
            }
        }
        ToolbarItem(placement: .automatic) {
            Picker("View", selection: $viewMode) {
                ForEach(CatalogViewMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        if plexServer.usesLivePlexAPI, !plexServer.isDownloadsServer {
            ToolbarItem(placement: .automatic) {
                watchFilterMenu
            }
        }
        if supportsLibraryFilters {
            ToolbarItem(placement: .automatic) {
                genreFilterMenu
            }
            ToolbarItem(placement: .automatic) {
                yearFilterMenu
            }
        }
        ToolbarItem(placement: .automatic) {
            sortOrderMenu
        }
        if showsCollectionsLink {
            ToolbarItem(placement: .automatic) {
                Button {
                    catalogNavigationActions.pushRoute(.libraryCollections(library: library))
                } label: {
                    Label("Collections", systemImage: "square.stack.3d.up")
                }
            }
        }
    }

    private var catalogOptionsMenu: some View {
        Menu {
            if let groupKey = downloadsShowGroupKey {
                Button("Delete show", role: .destructive) {
                    requestDeleteShow(groupKey: groupKey)
                }
                Divider()
            }
            Picker("View", selection: $viewMode) {
                ForEach(CatalogViewMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            }
            if plexServer.usesLivePlexAPI, !plexServer.isDownloadsServer {
                watchFilterMenu
            }
            if supportsLibraryFilters {
                genreFilterMenu
                yearFilterMenu
            }
            sortOrderMenu
        } label: {
            Label("Catalog options", systemImage: "ellipsis.circle")
        }
    }

    private var genreFilterMenu: some View {
        Menu {
            Button {
                listFilters.genreFilterKey = nil
            } label: {
                if listFilters.genreFilterKey == nil {
                    Label("All genres", systemImage: "checkmark")
                } else {
                    Text("All genres")
                }
            }
            if !availableGenres.isEmpty {
                Divider()
                ForEach(availableGenres) { genre in
                    Button {
                        listFilters.genreFilterKey = genre.filterKey
                    } label: {
                        if listFilters.genreFilterKey == genre.filterKey {
                            Label(genre.title, systemImage: "checkmark")
                        } else {
                            Text(genre.title)
                        }
                    }
                }
            }
        } label: {
            let title = availableGenres.first(where: { $0.filterKey == listFilters.genreFilterKey })?.title ?? "Genre"
            Label(title, systemImage: "tag")
        }
    }

    private var yearFilterMenu: some View {
        Menu {
            Button {
                listFilters.year = nil
            } label: {
                if listFilters.year == nil {
                    Label("All years", systemImage: "checkmark")
                } else {
                    Text("All years")
                }
            }
            Divider()
            ForEach(yearFilterOptions, id: \.self) { year in
                Button {
                    listFilters.year = year
                } label: {
                    if listFilters.year == year {
                        Label(String(year), systemImage: "checkmark")
                    } else {
                        Text(String(year))
                    }
                }
            }
        } label: {
            let title = listFilters.year.map(String.init) ?? "Year"
            Label(title, systemImage: "calendar")
        }
    }

    private var watchFilterMenu: some View {
        Menu {
            ForEach(CatalogWatchFilter.allCases) { option in
                Button {
                    watchFilter = option
                } label: {
                    if watchFilter == option {
                        Label(option.menuTitle, systemImage: "checkmark")
                    } else {
                        Text(option.menuTitle)
                    }
                }
            }
        } label: {
            Label("Filter: \(watchFilter.shortTitle)", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    private var sortOrderMenu: some View {
        Menu {
            ForEach(CatalogSort.allCases) { option in
                Button {
                    sortOrder = option
                } label: {
                    if sortOrder == option {
                        Label(option.menuTitle, systemImage: "checkmark")
                    } else {
                        Text(option.menuTitle)
                    }
                }
            }
        } label: {
            Label("Sort: \(sortOrder.shortTitle)", systemImage: "arrow.up.arrow.down")
        }
    }

    @MainActor
    private func reloadCatalog() async {
        loadSavedWatchFilter()
        let identity = reloadIdentityKey
        let isIdentityChange = identity != lastReloadIdentity
        lastReloadIdentity = identity
        if isIdentityChange {
            liveLoadedNodes = nil
        }
        liveLoadError = nil
        if plexServer.isDownloadsServer {
            liveLoadedNodes = OfflineDownloadCatalog.nodes(
                records: downloadManager.records,
                library: library,
                parent: parent
            )
            recomputeDisplayedNodes()
            return
        }
        catalogHasMore = false
        catalogNextOffset = 0
        guard plexServer.usesLivePlexAPI else { return }
        do {
            let client = try PlexMediaServerClient(server: plexServer)
            if supportsPagedCatalog {
                let page = try await client.fetchCatalogPage(
                    library: library,
                    parent: parent,
                    watchFilter: watchFilter,
                    listFilters: listFilters,
                    offset: 0
                )
                guard !Task.isCancelled else { return }
                liveLoadedNodes = page.nodes
                catalogNextOffset = page.nextOffset
                catalogHasMore = page.hasMore
            } else {
                let nodes = try await client.catalogNodes(
                    library: library,
                    parent: parent,
                    watchFilter: watchFilter,
                    listFilters: listFilters
                )
                guard !Task.isCancelled else { return }
                liveLoadedNodes = nodes
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            liveLoadError = error.localizedDescription
            liveLoadedNodes = []
            AppToastCenter.show("Couldn’t load library: \(error.localizedDescription)")
        }
        recomputeDisplayedNodes()
    }

    @MainActor
    private func loadMoreCatalog() async {
        guard supportsPagedCatalog, catalogHasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let client = try PlexMediaServerClient(server: plexServer)
            let page = try await client.fetchCatalogPage(
                library: library,
                parent: parent,
                watchFilter: watchFilter,
                listFilters: listFilters,
                offset: catalogNextOffset
            )
            guard !Task.isCancelled else { return }
            liveLoadedNodes = (liveLoadedNodes ?? []) + page.nodes
            catalogNextOffset = page.nextOffset
            catalogHasMore = page.hasMore
            recomputeDisplayedNodes()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            AppToastCenter.show("Couldn't load more: \(error.localizedDescription)")
        }
    }

    private func loadMoreIfNeeded(appeared node: PlexCatalogNode) {
        guard supportsPagedCatalog, catalogHasMore, !isLoadingMore else { return }
        guard (liveLoadedNodes?.count ?? 0) >= 40 else { return }
        guard let last = displayedNodes.last, last.id == node.id else { return }
        Task { await loadMoreCatalog() }
    }

    @MainActor
    private func loadGenreFiltersIfNeeded() async {
        guard supportsLibraryFilters else {
            availableGenres = []
            return
        }
        do {
            let client = try PlexMediaServerClient(server: plexServer)
            let genres = try await client.fetchLibraryGenres(library: library)
            guard !Task.isCancelled else { return }
            availableGenres = genres
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            availableGenres = []
        }
    }

    private func loadSavedListFilters() {
        let genre = UserDefaults.standard.string(forKey: "\(listFiltersStorageKey).genre")
        let year = UserDefaults.standard.object(forKey: "\(listFiltersStorageKey).year") as? Int
        listFilters = CatalogListFilters(
            genreFilterKey: genre?.isEmpty == true ? nil : genre,
            year: year
        )
    }

    private func saveListFilters(_ filters: CatalogListFilters) {
        if let genre = filters.genreFilterKey {
            UserDefaults.standard.set(genre, forKey: "\(listFiltersStorageKey).genre")
        } else {
            UserDefaults.standard.removeObject(forKey: "\(listFiltersStorageKey).genre")
        }
        if let year = filters.year {
            UserDefaults.standard.set(year, forKey: "\(listFiltersStorageKey).year")
        } else {
            UserDefaults.standard.removeObject(forKey: "\(listFiltersStorageKey).year")
        }
    }

    private func loadSavedSortOrder() {
        guard let raw = UserDefaults.standard.string(forKey: sortStorageKey),
              let saved = CatalogSort(rawValue: raw)
        else { return }
        sortOrder = saved
    }

    private func loadSavedWatchFilter() {
        guard let raw = UserDefaults.standard.string(forKey: watchFilterStorageKey),
              let saved = CatalogWatchFilter(rawValue: raw)
        else { return }
        watchFilter = saved
    }

    private func loadSavedViewMode() {
        if let saved = CatalogBrowsePreferences.loadViewMode(
            serverId: plexServer.id,
            libraryId: library.id,
            parent: parent
        ) {
            viewMode = saved
            return
        }
        viewMode = CatalogBrowsePreferences.defaultViewMode(parent: parent)
    }

    private func saveViewMode(_ mode: CatalogViewMode) {
        CatalogBrowsePreferences.saveViewMode(
            mode,
            serverId: plexServer.id,
            libraryId: library.id,
            parent: parent
        )
    }

    private var listContent: some View {
        Group {
            switch viewMode {
            case .list:
                catalogListModeView
            case .grid:
                catalogGridModeView
            }
        }
#if os(tvOS)
        .tvBrowseFocusSection(.catalog)
#endif
    }

    private var catalogListModeView: some View {
        ScrollViewReader { proxy in
            List {
                // Iterates the pre-built indexed cache; no per-body Array
                // allocation, and the redundant `.id(node.id)` was dropped
                // because `ForEach` already keys by `IndexedCatalogNode.id`
                // (which is `node.id`). Stacking an explicit `.id` on top
                // previously forced SwiftUI to tear down rows on every
                // filter/sort change instead of diffing them.
                ForEach(indexedDisplayedNodes) { entry in
                    row(
                        for: entry.node,
                        itemLibrary: library,
                        showLibraryInRow: false,
                        catalogFocusIndex: entry.index
                    )
                    .onAppear {
                        loadMoreIfNeeded(appeared: entry.node)
                    }
                }
                if catalogHasMore {
                    catalogLoadMoreRow
                }
            }
            .onChange(of: focusCoordinator.catalogFocusedIndex) { _, index in
                scrollCatalogFocus(to: index, proxy: proxy)
            }
        }
    }

    private var catalogGridModeView: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 20) {
                        ForEach(indexedDisplayedNodes) { entry in
                            gridCell(for: entry.node, catalogFocusIndex: entry.index)
                                .padding(6)
                                .onAppear {
                                    loadMoreIfNeeded(appeared: entry.node)
                                }
                        }
                        if catalogHasMore {
                            ProgressView()
                                .gridCellColumns(2)
                                .onAppear {
                                    Task { await loadMoreCatalog() }
                                }
                        }
                    }
                    .padding()
                }
                .onAppear {
                    updateGridColumnCount(width: geometry.size.width)
                }
                .onChange(of: geometry.size.width) { _, width in
                    updateGridColumnCount(width: width)
                }
                .onChange(of: focusCoordinator.catalogFocusedIndex) { _, index in
                    scrollCatalogFocus(to: index, proxy: proxy)
                }
            }
        }
    }

    private var catalogLoadMoreRow: some View {
        HStack {
            Spacer()
            if isLoadingMore {
                ProgressView()
            } else {
                Text("Load more…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .onAppear {
            Task { await loadMoreCatalog() }
        }
    }

    private func scrollCatalogFocus(to index: Int, proxy: ScrollViewProxy) {
        guard focusCoordinator.route == .catalogList,
              displayedNodes.indices.contains(index)
        else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(displayedNodes[index].id, anchor: .center)
        }
    }

    private func updateGridColumnCount(width: CGFloat) {
        catalogGridColumnCount = gridColumnCount(forWidth: width)
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 16)]
    }

    static func gridColumnCount(forWidth width: CGFloat) -> Int {
        let cellWidth: CGFloat = 140
        let spacing: CGFloat = 16
        let padding: CGFloat = 32
        return max(1, Int((width - padding + spacing) / (cellWidth + spacing)))
    }

    private func gridColumnCount(forWidth width: CGFloat) -> Int {
        Self.gridColumnCount(forWidth: width)
    }

    @ViewBuilder
    private func gridCell(for node: PlexCatalogNode, catalogFocusIndex: Int) -> some View {
        CatalogGridTile(
            plexServer: plexServer,
            node: node,
            sectionType: library.sectionType,
            catalogFocusIndex: catalogFocusIndex,
            isDownloaded: isDownloaded(node),
            artworkServer: artworkServer(for: node),
            route: catalogRoute(for: node)
        )
        .equatable()
    }

    private func isDownloaded(_ node: PlexCatalogNode) -> Bool {
        guard !plexServer.isDownloadsServer,
              let ratingKey = node.playbackRatingKey else { return false }
        return downloadManager.isDownloaded(serverId: plexServer.id, ratingKey: ratingKey)
    }

    private func artworkServer(for node: PlexCatalogNode) -> PlexServer? {
        guard plexServer.isDownloadsServer else { return nil }
        if let ratingKey = node.playbackRatingKey,
           let record = downloadManager.record(forCatalogRatingKey: ratingKey) {
            return downloadManager.server(for: record)
        }
        if case .show(let show) = node,
           let groupKey = OfflineDownloadCatalog.showGroupKey(fromCatalogRatingKey: show.ratingKey),
           let record = downloadManager.records.first(where: { $0.showGroupKey == groupKey && $0.isPlayable }) {
            return downloadManager.server(for: record)
        }
        return nil
    }

    private func originServerLabel(for node: PlexCatalogNode) -> String? {
        guard plexServer.isDownloadsServer,
              let ratingKey = node.playbackRatingKey,
              let record = downloadManager.record(forCatalogRatingKey: ratingKey)
        else { return nil }
        return "From \(record.serverName)"
    }

    private func catalogRoute(for node: PlexCatalogNode) -> CatalogNavigationRoute {
        switch node {
        case .show(let show):
            if plexServer.isDownloadsServer {
                return .browse(
                    library: library,
                    parent: .show(ratingKey: show.ratingKey),
                    navigationTitle: show.title
                )
            }
            return .showDetail(library: library, show: show)
        case .season(let season):
            return .browse(
                library: library,
                parent: .season(ratingKey: season.ratingKey),
                navigationTitle: "\(season.showTitle) · \(season.title)"
            )
        case .movie, .episode, .musicTrack, .photo:
            return .media(library: library, node: node)
        case .photo:
            return .media(library: library, node: node)
        }
    }

    #if DEBUG
    private var debugFixtureListContent: some View {
        let nodes = PlexSampleData.catalogNodes(for: library, parent: parent)
        let filtered = trimmedSearch.isEmpty
            ? nodes
            : nodes.filter { $0.matchesSearch(trimmedQuery: trimmedSearch) }
        return List {
            ForEach(Self.sortedNodes(filtered, by: sortOrder)) { node in
                row(for: node, itemLibrary: library, showLibraryInRow: false)
            }
        }
    }
    #endif

    @ViewBuilder
    private func row(
        for node: PlexCatalogNode,
        itemLibrary: PlexLibrary,
        showLibraryInRow: Bool,
        catalogFocusIndex: Int? = nil
    ) -> some View {
        let badge = showLibraryInRow ? itemLibrary.title : originServerLabel(for: node)
        // Focus state is read inside `CatalogListRowFocusOverlay` /
        // `CatalogListRowPhotoButton` instead of here. Reading it directly in
        // this @ViewBuilder bound the parent body to every focus tick, which
        // invalidated *all* visible rows on every arrow-key press. The grid
        // path was fixed earlier via `CatalogTileFocusOverlay`; list mode
        // mirrors that pattern now.
        switch node {
        case .show:
            CatalogListRowFocusOverlay(focusIndex: catalogFocusIndex) {
                NavigationLink(value: catalogRoute(for: node)) {
                    CatalogRowView(
                        plexServer: plexServer,
                        node: node,
                        artworkServer: artworkServer(for: node),
                        libraryContextTitle: badge,
                        showsDownloadedBadge: isDownloaded(node)
                    )
                    .contentShape(Rectangle())
                    .catalogMetadataAdminContextMenu(
                        plexServer: plexServer,
                        node: node,
                        sectionType: library.sectionType
                    ) {
                        if plexServer.isDownloadsServer,
                           case .show(let show) = node,
                           let groupKey = OfflineDownloadCatalog.showGroupKey(fromCatalogRatingKey: show.ratingKey) {
                            Button("Delete show", role: .destructive) {
                                requestDeleteShow(groupKey: groupKey)
                            }
                        }
                    }
                }
            }
            .accessibilityLabel(node.galleryAccessibilityLabel)
            .accessibilityIdentifier(catalogFocusAccessibilityID(for: catalogFocusIndex))
        case .season(let season):
            CatalogListRowFocusOverlay(focusIndex: catalogFocusIndex) {
                NavigationLink(
                    value: CatalogNavigationRoute.browse(
                        library: itemLibrary,
                        parent: .season(ratingKey: season.ratingKey),
                        navigationTitle: "\(season.showTitle) · \(season.title)"
                    )
                ) {
                    CatalogRowView(
                        plexServer: plexServer,
                        node: node,
                        artworkServer: artworkServer(for: node),
                        libraryContextTitle: badge,
                        showsDownloadedBadge: false
                    )
                }
            }
            .accessibilityLabel(node.galleryAccessibilityLabel)
            .accessibilityIdentifier(catalogFocusAccessibilityID(for: catalogFocusIndex))
        case .photo(let photo):
            CatalogListRowPhotoButton(focusIndex: catalogFocusIndex) {
                photoSlideshowStartIndex = displayedNodes.firstIndex(where: { $0.id == node.id })
                showPhotoSlideshow = true
            } label: {
                CatalogRowView(
                    plexServer: plexServer,
                    node: node,
                    artworkServer: artworkServer(for: node),
                    libraryContextTitle: badge,
                    showsDownloadedBadge: false
                )
            }
            .accessibilityLabel(photo.title)
        case .movie, .episode:
            CatalogListRowFocusOverlay(focusIndex: catalogFocusIndex) {
                NavigationLink(value: CatalogNavigationRoute.media(library: itemLibrary, node: node)) {
                    CatalogRowView(
                        plexServer: plexServer,
                        node: node,
                        artworkServer: artworkServer(for: node),
                        libraryContextTitle: badge,
                        showsDownloadedBadge: isDownloaded(node)
                    )
                    .contentShape(Rectangle())
                    .catalogMetadataAdminContextMenu(
                        plexServer: plexServer,
                        node: node,
                        sectionType: library.sectionType
                    )
                }
            }
            .accessibilityLabel(node.galleryAccessibilityLabel)
            .accessibilityIdentifier(catalogFocusAccessibilityID(for: catalogFocusIndex))
        case .musicTrack:
            CatalogListRowFocusOverlay(focusIndex: catalogFocusIndex) {
                NavigationLink(value: CatalogNavigationRoute.media(library: itemLibrary, node: node)) {
                    CatalogRowView(
                        plexServer: plexServer,
                        node: node,
                        artworkServer: artworkServer(for: node),
                        libraryContextTitle: badge,
                        showsDownloadedBadge: isDownloaded(node)
                    )
                }
            }
            .accessibilityLabel(node.galleryAccessibilityLabel)
            .accessibilityIdentifier(catalogFocusAccessibilityID(for: catalogFocusIndex))
        }
    }

    private func catalogFocusAccessibilityID(for index: Int?) -> String {
        guard let index else { return "" }
        return "catalogItem.\(index)"
    }
}

// MARK: - Sort helpers

extension CatalogListView {
    fileprivate static func sortedNodes(_ nodes: [PlexCatalogNode], by sortOrder: CatalogSort) -> [PlexCatalogNode] {
        switch sortOrder {
        case .plexDefault:
            return nodes.sorted { $0.libraryOrder < $1.libraryOrder }
        case .titleAscending:
            return nodes.sorted {
                $0.listTitle.localizedCaseInsensitiveCompare($1.listTitle) == .orderedAscending
            }
        case .titleDescending:
            return nodes.sorted {
                $0.listTitle.localizedCaseInsensitiveCompare($1.listTitle) == .orderedDescending
            }
        case .yearDescending:
            return nodes.sorted { lhs, rhs in
                let ly = lhs.listYear ?? 0
                let ry = rhs.listYear ?? 0
                if ly != ry { return ly > ry }
                return titleAscending(lhs, rhs)
            }
        case .yearAscending:
            return nodes.sorted { lhs, rhs in
                let ly = lhs.listYear ?? Int.max
                let ry = rhs.listYear ?? Int.max
                if ly != ry { return ly < ry }
                return titleAscending(lhs, rhs)
            }
        case .dateAddedDescending:
            return nodes.sorted { lhs, rhs in
                compareUnixDescending(lhs.listAddedAt, rhs.listAddedAt, tieBreak: titleAscending(lhs, rhs))
            }
        case .dateAddedAscending:
            return nodes.sorted { lhs, rhs in
                compareUnixAscending(lhs.listAddedAt, rhs.listAddedAt, tieBreak: titleAscending(lhs, rhs))
            }
        case .releaseDateDescending:
            return nodes.sorted { lhs, rhs in
                compareUnixDescending(
                    lhs.listOriginallyAvailableAt,
                    rhs.listOriginallyAvailableAt,
                    tieBreak: titleAscending(lhs, rhs)
                )
            }
        case .releaseDateAscending:
            return nodes.sorted { lhs, rhs in
                compareUnixAscending(
                    lhs.listOriginallyAvailableAt,
                    rhs.listOriginallyAvailableAt,
                    tieBreak: titleAscending(lhs, rhs)
                )
            }
        case .seasonEpisode:
            return nodes.sorted { lhs, rhs in
                let lo = lhs.listSeasonEpisodeOrder ?? (0, 0)
                let ro = rhs.listSeasonEpisodeOrder ?? (0, 0)
                if lo.season != ro.season { return lo.season < ro.season }
                if lo.episode != ro.episode { return lo.episode < ro.episode }
                return titleAscending(lhs, rhs)
            }
        }
    }
}

private func titleAscending(_ lhs: PlexCatalogNode, _ rhs: PlexCatalogNode) -> Bool {
    lhs.listTitle.localizedCaseInsensitiveCompare(rhs.listTitle) == .orderedAscending
}

private func compareUnixDescending(_ lhs: Int?, _ rhs: Int?, tieBreak: Bool) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        if l != r { return l > r }
        return tieBreak
    case (nil, _?): return false
    case (_?, nil): return true
    case (nil, nil): return tieBreak
    }
}

private func compareUnixAscending(_ lhs: Int?, _ rhs: Int?, tieBreak: Bool) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        if l != r { return l < r }
        return tieBreak
    case (nil, _?): return false
    case (_?, nil): return true
    case (nil, nil): return tieBreak
    }
}

// MARK: - Row

struct CatalogRowView: View {
    let plexServer: PlexServer
    let node: PlexCatalogNode
    var artworkServer: PlexServer? = nil
    var libraryContextTitle: String? = nil
    var showsDownloadedBadge: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CatalogArtworkImage(
                plexServer: plexServer,
                thumbPath: node.listThumbPath,
                artworkServer: artworkServer,
                style: .list,
                watchProgressFraction: node.watchProgressFraction,
                showsDownloadedBadge: showsDownloadedBadge
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(node.listTitle)
                    .foregroundStyle(.primary)
                if let subtitle = node.listSubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let lib = libraryContextTitle {
                    Text(lib)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// A single catalog grid tile, extracted as its own view so the parent
/// `CatalogListView` (which observes `KeyboardFocusCoordinator`) doesn't drag
/// every cell's body through SwiftUI's diff on each focus change. The focus
/// ring is applied in `CatalogTileFocusOverlay`, which is the only thing that
/// observes the coordinator.
private struct CatalogGridTile: View, Equatable {
    let plexServer: PlexServer
    let node: PlexCatalogNode
    let sectionType: PlexSectionType
    let catalogFocusIndex: Int
    let isDownloaded: Bool
    let artworkServer: PlexServer?
    let route: CatalogNavigationRoute

    var body: some View {
        CatalogTileFocusOverlay(focusIndex: catalogFocusIndex, chrome: .catalogPoster) {
            NavigationLink(value: route) {
                VStack(alignment: .leading, spacing: 8) {
                    CatalogArtworkImage(
                        plexServer: plexServer,
                        thumbPath: node.listThumbPath,
                        artworkServer: artworkServer,
                        style: .hubTile,
                        watchProgressFraction: node.watchProgressFraction,
                        showsDownloadedBadge: isDownloaded
                    )
                    Text(node.listTitle)
                        .font(.caption.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.primary)
                    if let subtitle = node.listSubtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .contentShape(Rectangle())
                .catalogMetadataAdminContextMenu(
                    plexServer: plexServer,
                    node: node,
                    sectionType: sectionType
                )
            }
            .buttonStyle(.plain)
        }
#if os(tvOS)
        .tvCatalogTileFocus()
#endif
        .accessibilityLabel(node.galleryAccessibilityLabel)
        .accessibilityHint("Open item")
        .accessibilityIdentifier("catalogItem.\(catalogFocusIndex)")
    }
}

/// Tiny isolation point for the focus highlight: only this subview observes
/// `KeyboardFocusCoordinator`, so a focused-index change doesn't invalidate
/// the entire enclosing cell.
private struct CatalogTileFocusOverlay<Content: View>: View {
    @EnvironmentObject private var focusCoordinator: KeyboardFocusCoordinator
    let focusIndex: Int
    let chrome: BrowseFocusChrome
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .browseFocusHighlight(
                active: focusCoordinator.catalogFocusActive(forIndex: focusIndex),
                chrome: chrome
            )
    }
}

/// Cached `(index, node)` pair so `ForEach` can iterate without allocating a
/// fresh `Array(enumerated())` on every body. Identifiable by node id so the
/// list still diffs by stable identity across filter / sort transitions.
private struct IndexedCatalogNode: Identifiable, Equatable {
    let index: Int
    let node: PlexCatalogNode
    var id: String { node.id }
}

/// List-row equivalent of `CatalogTileFocusOverlay`. Keeps the focus-ring
/// dependency out of `CatalogListView.row(for:)` so the parent body doesn't
/// re-evaluate every visible row on each arrow-key focus change.
private struct CatalogListRowFocusOverlay<Content: View>: View {
    @EnvironmentObject private var focusCoordinator: KeyboardFocusCoordinator
    let focusIndex: Int?
    @ViewBuilder let content: () -> Content

    var body: some View {
        let active = focusIndex.map { focusCoordinator.catalogFocusActive(forIndex: $0) } ?? false
        content().browseFocusHighlight(active: active, chrome: .catalogListRow)
    }
}

/// Photo cells use a button style that takes `focused` up front, so they need
/// their own focus-observing wrapper instead of `browseFocusHighlight`.
private struct CatalogListRowPhotoButton<Label: View>: View {
    @EnvironmentObject private var focusCoordinator: KeyboardFocusCoordinator
    let focusIndex: Int?
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        let active = focusIndex.map { focusCoordinator.catalogFocusActive(forIndex: $0) } ?? false
        Button(action: action, label: label)
            .buttonStyle(.browsePressable(focused: active, chrome: .catalogListRow))
    }
}

#Preview("Movie library") {
    NavigationStack {
        let server = PlexSampleData.servers[0]
        let lib = PlexSampleData.libraries(for: server.id)[0]
        CatalogListView(
            plexServer: server,
            library: lib,
            parent: .root,
            navigationTitle: lib.title
        )
        .environmentObject(OfflineDownloadManager())
    }
}

#Preview("TV library") {
    NavigationStack {
        let server = PlexSampleData.servers[0]
        let lib = PlexSampleData.libraries(for: server.id)[1]
        CatalogListView(
            plexServer: server,
            library: lib,
            parent: .root,
            navigationTitle: lib.title
        )
        .environmentObject(OfflineDownloadManager())
    }
}
