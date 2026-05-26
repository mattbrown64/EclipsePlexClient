//
//  LibraryDetailView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Library root shell: Recommended, Browse, and optional Collections tabs (Plex-style).
struct LibraryDetailView: View {
    let plexServer: PlexServer
    let library: PlexLibrary

    @State private var selectedTab: LibraryRootTab = .recommended

    @EnvironmentObject private var focusCoordinator: KeyboardFocusCoordinator

    private var availableTabs: [LibraryRootTab] {
        var tabs: [LibraryRootTab] = []
        if LibraryBrowsePreferences.showsRecommendedTab(
            sectionType: library.sectionType,
            usesLiveAPI: plexServer.usesLivePlexAPI && !plexServer.isDownloadsServer
        ) {
            tabs.append(.recommended)
        }
        tabs.append(.browse)
        if LibraryBrowsePreferences.showsCollectionsTab(sectionType: library.sectionType),
           plexServer.usesLivePlexAPI,
           !plexServer.isDownloadsServer {
            tabs.append(.collections)
        }
        return tabs
    }

    var body: some View {
        VStack(spacing: 0) {
            if availableTabs.count > 1 {
                Picker("Library section", selection: $selectedTab) {
                    ForEach(availableTabs) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .onChange(of: selectedTab) { _, tab in
                    LibraryBrowsePreferences.saveRootTab(tab, serverId: plexServer.id, libraryId: library.id)
                    adoptFocus(for: tab)
                }
            }

            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(library.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .browseMenuToolbar()
        .onAppear {
            loadSavedTab()
            adoptFocus(for: selectedTab)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch effectiveTab {
        case .recommended:
            LibraryRecommendedView(plexServer: plexServer, library: library)
        case .browse:
            CatalogListView(
                plexServer: plexServer,
                library: library,
                parent: .root,
                navigationTitle: library.title,
                embedInLibraryShell: true
            )
        case .collections:
            LibraryCollectionsView(plexServer: plexServer, library: library, embedInLibraryShell: true)
        }
    }

    private var effectiveTab: LibraryRootTab {
        availableTabs.contains(selectedTab) ? selectedTab : (availableTabs.first ?? .browse)
    }

    private func loadSavedTab() {
        if let saved = LibraryBrowsePreferences.loadRootTab(serverId: plexServer.id, libraryId: library.id),
           availableTabs.contains(saved) {
            selectedTab = saved
        } else if availableTabs.contains(.recommended) {
            selectedTab = .recommended
        } else {
            selectedTab = .browse
        }
    }

    /// Avoid same-frame `focusCoordinator.route` flips that previously fired
    /// the SwiftUI "onChange(of: AppFocusRoute) action tried to update multiple
    /// times per frame" warning during library selection. RootShellView already
    /// sets the route during `selectLibrary`, then this view's `onAppear` ran
    /// in the same pass — re-writing the route inline caused observers
    /// (notably `AppSidebarView`) to fire mid-update. Skip when the coordinator
    /// is already on the right pane, and otherwise defer to the next runloop.
    private func adoptFocus(for tab: LibraryRootTab) {
        let target: AppFocusRoute = (tab == .recommended) ? .homeHubs : .catalogList
        guard focusCoordinator.route != target else { return }
        DispatchQueue.main.async {
            switch tab {
            case .recommended:
                focusCoordinator.focusHome()
            case .browse, .collections:
                focusCoordinator.focusCatalog()
            }
        }
    }
}
