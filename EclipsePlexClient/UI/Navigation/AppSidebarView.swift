//
//  AppSidebarView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Single sidebar: sources, then Home + libraries for the selected source (catalog stays in the detail column).
struct AppSidebarView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var focusCoordinator: KeyboardFocusCoordinator
#if os(tvOS)
    @FocusState private var tvSidebarFocusedRowID: String?
#endif

    let deviceServers: [PlexServer]
    let plexServers: [PlexServer]
    let selectedServer: PlexServer?
    let libraries: [PlexLibrary]

    @Binding var selectedServerID: UUID?
    @Binding var selectedLibraryID: String?
    /// Library id whose row should show an in-flight spinner (set on tap,
    /// cleared when the detail column finishes presenting that library).
    var pendingLibraryID: String? = nil

    var isLoadingLibraries: Bool = false
    var librariesLoadError: String?
    var showsLibrariesError: Bool = false

    var isUserAddedServer: (UUID) -> Bool = { _ in false }
    var serverReachable: (UUID) -> Bool? = { _ in nil }
    var serverLastOnlineAt: (UUID) -> Date? = { _ in nil }
    var onSelectServer: (UUID) -> Void = { _ in }
    var onSelectHome: () -> Void = {}
    var onSelectPlaylists: () -> Void = {}
    var onSelectLibrary: (PlexLibrary) -> Void = { _ in }
    var onEditServer: (PlexServer) -> Void = { _ in }
    var onManageServer: (PlexServer) -> Void = { _ in }
    var onRemoveServer: (UUID) -> Void = { _ in }
    var onDismissSidebar: () -> Void = {}
    var activeDownloadCount: Int = 0
    var onSelectAllServersHome: () -> Void = {}
    var onSelectSettings: () -> Void = {}
    var onRetryLibraries: () -> Void = {}
    var isAggregateHomeSelected: Bool = false

    private var isHomeSelected: Bool {
        selectedLibraryID == nil && !isAggregateHomeSelected
    }

    /// Cached focus rows. Previously this was a computed property that ran
    /// `buildSidebarFocusRows()` on every body — and `body` referenced it
    /// twice (`serverButton`, `rowButton`) so each render rebuilt the closure
    /// array twice plus once per `onChange` trigger. Caching as `@State` and
    /// refreshing only from the explicit triggers below cuts that down to one
    /// allocation per actual data change.
    @State private var sidebarFocusRows: [SidebarFocusRow] = []

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        ScrollViewReader { scrollProxy in
            sidebarList
                .onChange(of: focusCoordinator.sidebarFocusedIndex) { _, _ in
                    scrollSidebarFocus(into: scrollProxy)
#if os(tvOS)
                    syncTVSidebarFocusFromCoordinator()
#endif
                }
                .onChange(of: focusCoordinator.route) { _, route in
                    if route == .sidebar {
                        scrollSidebarFocus(into: scrollProxy)
#if os(tvOS)
                        syncTVSidebarFocusFromCoordinator()
#endif
                    }
                }
        }
    }

    private var sidebarList: some View {
        List {
            Section {
                HStack {
                    Spacer(minLength: 0)
                    EclipsePlexBrandingHeader(layout: .compact)
                    Spacer(minLength: 0)
                }
                .listRowBackground(Color.clear)
            }

            if !deviceServers.isEmpty {
                Section {
                    ForEach(deviceServers) { server in
                        serverButton(
                            server,
                            focusRowID: FocusRowID.downloadsServer(server.id),
                            isReachable: nil,
                            badge: activeDownloadCount
                        )
                    }
                } header: {
                    Text("Downloads")
                } footer: {
                    if activeDownloadCount > 0 {
                        Text("\(activeDownloadCount) active")
                    }
                }
            }

            Section {
                rowButton(
                    title: "Home",
                    systemImage: "house.circle",
                    subtitle: "All servers",
                    focusRowID: FocusRowID.aggregateHome,
                    isSelected: isAggregateHomeSelected
                ) {
                    onSelectAllServersHome()
                }
            }

            Section("Plex servers") {
                ForEach(plexServers) { server in
                    serverButton(
                        server,
                        focusRowID: FocusRowID.plexServer(server.id),
                        isReachable: serverReachable(server.id)
                    )
                    .contextMenu {
                        if server.usesLivePlexAPI {
                            Button("Server management…") {
                                onManageServer(server)
                            }
                        }
                        if isUserAddedServer(server.id) {
                            Button("Edit Server…") {
                                onEditServer(server)
                            }
                            Button("Remove Server", role: .destructive) {
                                onRemoveServer(server.id)
                            }
                        }
                    }
                }
            }

            if let selectedServer {
                Section(selectedServer.name) {
                    rowButton(
                        title: "Home",
                        systemImage: "house",
                        subtitle: "Continue Watching & hubs",
                        focusRowID: FocusRowID.serverHome,
                        isSelected: isHomeSelected
                    ) {
                        onSelectHome()
                    }

                    if isLoadingLibraries {
                        HStack {
                            ProgressView()
                            Text("Loading libraries…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if showsLibrariesError, let librariesLoadError {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(librariesLoadError)
                                .font(.caption)
                                .foregroundStyle(.red)
                            Button("Retry") {
                                onRetryLibraries()
                            }
                            .font(.caption)
                        }
                    }

                    ForEach(libraries) { library in
                        rowButton(
                            title: library.title,
                            systemImage: icon(for: library),
                            subtitle: nil,
                            focusRowID: FocusRowID.library(library.id),
                            isSelected: selectedLibraryID == library.id,
                            isPending: pendingLibraryID == library.id
                        ) {
                            onSelectLibrary(library)
                        }
                    }

                    if selectedServer.usesLivePlexAPI, !selectedServer.isDownloadsServer {
                        rowButton(
                            title: "Playlists",
                            systemImage: "music.note.list",
                            subtitle: "Server playlists",
                            focusRowID: FocusRowID.playlists,
                            isSelected: false
                        ) {
                            onSelectPlaylists()
                        }
                    }
                }
            }

            Section {
                rowButton(
                    title: "Settings",
                    systemImage: "gearshape",
                    subtitle: nil,
                    focusRowID: FocusRowID.settings,
                    isSelected: false
                ) {
                    onSelectSettings()
                }
            }
        }
#if os(tvOS)
        .tvBrowseFocusSection(.sidebar)
#endif
        .onAppear { syncSidebarFocusRows() }
        .onChange(of: selectedServerID) { _, _ in syncSidebarFocusRows() }
        .onChange(of: selectedLibraryID) { _, _ in syncSidebarFocusRows() }
        .onChange(of: libraries.map(\.id)) { _, _ in syncSidebarFocusRows() }
        .onChange(of: plexServers.map(\.id)) { _, _ in syncSidebarFocusRows() }
        .onChange(of: deviceServers.map(\.id)) { _, _ in syncSidebarFocusRows() }
        .navigationTitle("Browse")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    onDismissSidebar()
                    dismiss()
                }
            }
        }
#endif
    }

    private func syncSidebarFocusRows() {
        let rows = buildSidebarFocusRows()
        sidebarFocusRows = rows
        focusCoordinator.setSidebarRows(rows)
#if os(tvOS)
        syncTVSidebarFocusFromCoordinator()
#endif
    }

#if os(tvOS)
    private func syncTVSidebarFocusFromCoordinator() {
        guard focusCoordinator.route == .sidebar,
              focusCoordinator.sidebarRows.indices.contains(focusCoordinator.sidebarFocusedIndex)
        else { return }
        tvSidebarFocusedRowID = focusCoordinator.sidebarRows[focusCoordinator.sidebarFocusedIndex].id
    }
#endif

    private func serverButton(
        _ server: PlexServer,
        focusRowID: String,
        isReachable: Bool?,
        badge: Int = 0
    ) -> some View {
        Button {
            onSelectServer(server.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let isReachable {
                    Circle()
                        .fill(isReachable ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .foregroundStyle(.primary)
                    if isReachable == false, let lastOnline = serverLastOnlineAt(server.id) {
                        Text("Last online \(Self.relativeDateFormatter.localizedString(for: lastOnline, relativeTo: Date()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(server.hostDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2), in: Capsule())
                }
                if selectedServerID == server.id {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(
            .browsePressable(
                focused: isSidebarFocusActive(
                    rowID: focusRowID,
                    rows: sidebarFocusRows,
                    coordinator: focusCoordinator
                ),
                chrome: .sidebarRow
            )
        )
        .contentShape(Rectangle())
        .id(focusRowID)
        .accessibilityLabel(server.name)
        .accessibilityHint("Select server")
        .accessibilityIdentifier(focusRowID)
#if os(tvOS)
        .focused($tvSidebarFocusedRowID, equals: focusRowID)
#endif
    }

    private func scrollSidebarFocus(into proxy: ScrollViewProxy) {
        guard focusCoordinator.route == .sidebar,
              focusCoordinator.sidebarRows.indices.contains(focusCoordinator.sidebarFocusedIndex)
        else { return }
        let rowID = focusCoordinator.sidebarRows[focusCoordinator.sidebarFocusedIndex].id
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(rowID, anchor: .center)
        }
    }

    private func rowButton(
        title: String,
        systemImage: String,
        subtitle: String?,
        focusRowID: String,
        isSelected: Bool,
        isPending: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(title, systemImage: systemImage)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
                if isPending {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading")
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(
            .browsePressable(
                focused: isSidebarFocusActive(
                    rowID: focusRowID,
                    rows: sidebarFocusRows,
                    coordinator: focusCoordinator
                ),
                chrome: .sidebarRow
            )
        )
        .contentShape(Rectangle())
        .id(focusRowID)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle ?? "Open")
        .accessibilityIdentifier(focusRowID)
#if os(tvOS)
        .focused($tvSidebarFocusedRowID, equals: focusRowID)
#endif
    }

    private func icon(for library: PlexLibrary) -> String {
        switch library.sectionType {
        case .movie: "film"
        case .show: "tv"
        case .music: "music.note"
        case .photo: "photo"
        case .other: "folder"
        }
    }
}
