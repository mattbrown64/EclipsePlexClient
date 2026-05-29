//
//  AppSidebarView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Single sidebar: sources, then Home + libraries for the selected source (catalog stays in the detail column).
struct AppSidebarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeAccent) private var themeAccent
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
    var connectionIssueForServer: (PlexServer) -> PlexServerConnectionIssue? = { _ in nil }

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
    var onSignInToPlex: () -> Void = {}
    var isAggregateHomeSelected: Bool = false
    var menuControlsDisabled: Bool = false

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
    @AppStorage("favoriteLibraryIDsCSV") private var favoriteLibraryIDsRaw = ""

    private var favoriteLibraryIDs: Set<String> {
        Set(
            favoriteLibraryIDsRaw
                .split(separator: ",")
                .map { String($0) }
                .filter { !$0.isEmpty }
        )
    }

    private var favoriteLibraries: [PlexLibrary] {
        libraries.filter { favoriteLibraryIDs.contains($0.id) }
    }

    private var otherLibraries: [PlexLibrary] {
        libraries.filter { !favoriteLibraryIDs.contains($0.id) }
    }

    private var sidebarRevision: String {
        let libIDs = libraries.map(\.id).joined(separator: ",")
        let plexIDs = plexServers.map { $0.id.uuidString }.joined(separator: ",")
        let deviceIDs = deviceServers.map { $0.id.uuidString }.joined(separator: ",")
        return "\(selectedServerID?.uuidString ?? "nil")|\(selectedLibraryID ?? "nil")|\(libIDs)|\(plexIDs)|\(deviceIDs)"
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        ScrollViewReader { scrollProxy in
            sidebarList
                .onChange(of: focusCoordinator.sidebarFocusedIndex) { _, _ in
                    scheduleSidebarScroll(into: scrollProxy)
                }
                .onChange(of: focusCoordinator.route) { _, route in
                    guard route == .sidebar else { return }
                    scheduleSidebarScroll(into: scrollProxy)
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
                            connectionIssue: nil,
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
                        connectionIssue: connectionIssueForServer(server),
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

                    if let issue = connectionIssueForServer(selectedServer) {
                        serverConnectionBanner(issue, server: selectedServer)
                    } else if isLoadingLibraries {
                        HStack {
                            fixedProgressIndicator()
                            Text("Loading libraries…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if libraries.isEmpty, selectedServer.usesLivePlexAPI {
                        Text("No libraries on this server.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !favoriteLibraries.isEmpty {
                        Section("Favorites") {
                            ForEach(favoriteLibraries) { library in
                                libraryRow(library)
                            }
                        }
                    }

                    ForEach(otherLibraries) { library in
                        libraryRow(library)
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
        .onChange(of: sidebarRevision) { _, _ in syncSidebarFocusRows() }
        .navigationTitle("Browse")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    onDismissSidebar()
                    dismiss()
                }
                .disabled(menuControlsDisabled)
            }
        }
#endif
    }

    private func libraryRow(_ library: PlexLibrary) -> some View {
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
        .contextMenu {
            Button(favoriteLibraryIDs.contains(library.id) ? "Remove Favorite" : "Add Favorite") {
                toggleFavorite(library.id)
            }
        }
    }

    private func toggleFavorite(_ libraryID: String) {
        var favorites = favoriteLibraryIDs
        if favorites.contains(libraryID) {
            favorites.remove(libraryID)
        } else {
            favorites.insert(libraryID)
        }
        favoriteLibraryIDsRaw = favorites.sorted().joined(separator: ",")
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

    private func serverConnectionBanner(_ issue: PlexServerConnectionIssue, server: PlexServer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(issue.title, systemImage: issue.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text(issue.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                if issue.offersPlexAccountSignIn {
                    Button {
                        onSignInToPlex()
                    } label: {
                        Label("Sign in to Plex", systemImage: "person.badge.key")
                    }
                    .font(.caption)
                }
                if issue.needsEditServer {
                    Button("Edit Server") {
                        onEditServer(server)
                    }
                    .font(.caption)
                }
                if issue.canRetryLibraries {
                    Button("Retry") {
                        onRetryLibraries()
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func serverButton(
        _ server: PlexServer,
        focusRowID: String,
        connectionIssue: PlexServerConnectionIssue?,
        isReachable: Bool?,
        badge: Int = 0
    ) -> some View {
        Button {
            onSelectServer(server.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let color = serverStatusColor(connectionIssue: connectionIssue, isReachable: isReachable) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .foregroundStyle(.primary)
                    if let connectionIssue {
                        Text(connectionIssue.serverRowSubtitle)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    } else if isReachable == false, let lastOnline = serverLastOnlineAt(server.id) {
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
                        .background(themeAccent.opacity(0.2), in: Capsule())
                }
                if selectedServerID == server.id {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(themeAccent)
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

    private func serverStatusColor(
        connectionIssue: PlexServerConnectionIssue?,
        isReachable: Bool?
    ) -> Color? {
        if let connectionIssue {
            switch connectionIssue {
            case .missingToken, .invalidAddress, .librariesFailed:
                return .orange
            case .offline:
                return .red
            }
        }
        guard let isReachable else { return nil }
        return isReachable ? .green : .red
    }

    /// Defers `scrollTo` so AppKit layout is not re-entered from `onChange`.
    private func scheduleSidebarScroll(into proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            scrollSidebarFocus(into: proxy)
        }
    }

    private func scrollSidebarFocus(into proxy: ScrollViewProxy) {
        guard focusCoordinator.route == .sidebar,
              focusCoordinator.sidebarRows.indices.contains(focusCoordinator.sidebarFocusedIndex)
        else { return }
        let rowID = focusCoordinator.sidebarRows[focusCoordinator.sidebarFocusedIndex].id
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(rowID, anchor: .center)
        }
#if os(tvOS)
        syncTVSidebarFocusFromCoordinator()
#endif
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
                    fixedProgressIndicator()
                        .accessibilityLabel("Loading")
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(themeAccent)
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
