//
//  RootShellView.swift
//  EclipsePlexClient
//
//  Created by Matt Brown on 5/15/26.
//

import SwiftUI

/// Root UI: `NavigationSplitView` with Plex sidebar and detail (home or library).
///
/// `ContentView` (video demo) stays separate; open its `#Preview` or push it from the detail stack later.
struct RootShellView: View {
    @AppStorage("selectedPlexServerId") private var selectedServerIdString = ""
    @AppStorage("selectedPlexLibraryId") private var selectedLibraryIdString = ""

    /// Each app launch starts on the home detail; library id is cleared once when the shell first appears.
    @State private var hasClearedLibraryForThisSession = false

    @StateObject private var sidebarInteraction = SidebarInteractionState()
    @StateObject private var plexRegistry = PlexServerRegistry()

    @State private var showAddPlexServer = false

    /// User-controlled visibility when the sidebar is allowed; overridden to `.detailOnly` during playback.
    @State private var navigationSplitVisibility: NavigationSplitViewVisibility = .all

    private var plexServers: [PlexServer] { plexRegistry.allServers }

    private var selectedPlexServer: PlexServer? {
        guard let uuid = UUID(uuidString: selectedServerIdString) else { return nil }
        return plexServers.first { $0.id == uuid }
    }

    private var librariesForSelectedServer: [PlexLibrary] {
        guard let server = selectedPlexServer else { return [] }
        if server.usesLivePlexAPI {
            return plexRegistry.librariesByServerID[server.id] ?? []
        }
        return PlexSampleData.libraries(for: server.id)
    }

    private var selectedPlexLibrary: PlexLibrary? {
        guard !selectedLibraryIdString.isEmpty else { return nil }
        return librariesForSelectedServer.first { $0.id == selectedLibraryIdString }
    }

    private var selectedPlexServerIDBinding: Binding<UUID?> {
        Binding(
            get: { UUID(uuidString: selectedServerIdString) },
            set: { newValue in
                selectedServerIdString = newValue?.uuidString ?? ""
            }
        )
    }

    private var selectedPlexLibraryIDBinding: Binding<String?> {
        Binding(
            get: {
                selectedLibraryIdString.isEmpty ? nil : selectedLibraryIdString
            },
            set: { newValue in
                selectedLibraryIdString = newValue ?? ""
            }
        )
    }

    /// Clear library id when it does not exist for the current server; do **not** auto-select a library.
    private func invalidateLibrarySelectionIfNeeded() {
        let libs = librariesForSelectedServer
        guard !libs.isEmpty else {
            selectedLibraryIdString = ""
            return
        }
        if selectedLibraryIdString.isEmpty { return }
        if !libs.contains(where: { $0.id == selectedLibraryIdString }) {
            selectedLibraryIdString = ""
        }
    }

    /// While `suppressSidebarInteraction` is true, the sidebar column stays hidden and cannot be expanded.
    private var splitColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: {
                sidebarInteraction.suppressSidebarInteraction ? .detailOnly : navigationSplitVisibility
            },
            set: { newValue in
                guard !sidebarInteraction.suppressSidebarInteraction else { return }
                navigationSplitVisibility = newValue
            }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: splitColumnVisibility) {
            SidebarView(
                plexServers: plexServers,
                selectedPlexServerID: selectedPlexServerIDBinding,
                librariesForSelectedServer: librariesForSelectedServer,
                selectedPlexLibraryID: selectedPlexLibraryIDBinding,
                isLoadingLibraries: plexRegistry.librariesLoadingServerID == selectedPlexServer?.id,
                librariesLoadError: plexRegistry.librariesLoadError,
                librariesErrorServerID: plexRegistry.librariesLoadErrorServerID,
                selectedServerID: selectedPlexServer?.id,
                isUserAddedServer: { plexRegistry.isUserAddedServer(id: $0) },
                onRemoveServer: { id in
                    plexRegistry.removeCustomServer(id: id)
                    if selectedServerIdString == id.uuidString {
                        selectedServerIdString = plexServers.first?.id.uuidString ?? ""
                        selectedLibraryIdString = ""
                    }
                }
            )
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
#endif
        } detail: {
            NavigationStack {
                if let server = selectedPlexServer, let library = selectedPlexLibrary {
                    CatalogListView(
                        plexServer: server,
                        library: library,
                        parent: .root,
                        navigationTitle: library.title
                    )
                } else {
                    HomeDetailView(
                        plexServer: selectedPlexServer,
                        onAddPlexServer: { showAddPlexServer = true }
                    )
                }
            }
        }
        .environmentObject(sidebarInteraction)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddPlexServer = true
                } label: {
                    Label("Add Plex Server", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddPlexServer) {
            AddPlexServerSheet(registry: plexRegistry) { added in
                selectedServerIdString = added.id.uuidString
                selectedLibraryIdString = ""
            }
        }
        .onAppear {
            if selectedServerIdString.isEmpty, let first = plexServers.first {
                selectedServerIdString = first.id.uuidString
            }
            if !hasClearedLibraryForThisSession {
                selectedLibraryIdString = ""
                hasClearedLibraryForThisSession = true
            }
            invalidateLibrarySelectionIfNeeded()
        }
        .onChange(of: selectedServerIdString) { _, _ in
            selectedLibraryIdString = ""
            invalidateLibrarySelectionIfNeeded()
        }
        .task(id: selectedServerIdString) {
            guard let server = selectedPlexServer else { return }
            await plexRegistry.refreshLibraries(for: server)
        }
    }
}

#Preview {
    RootShellView()
}
