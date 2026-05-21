//
//  AppSidebarView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Single sidebar: sources, then Home + libraries for the selected source (catalog stays in the detail column).
struct AppSidebarView: View {
    @Environment(\.dismiss) private var dismiss

    let deviceServers: [PlexServer]
    let plexServers: [PlexServer]
    let selectedServer: PlexServer?
    let libraries: [PlexLibrary]

    @Binding var selectedServerID: UUID?
    @Binding var selectedLibraryID: String?

    var isLoadingLibraries: Bool = false
    var librariesLoadError: String?
    var showsLibrariesError: Bool = false

    var isUserAddedServer: (UUID) -> Bool = { _ in false }
    var serverReachable: (UUID) -> Bool? = { _ in nil }
    var onSelectServer: (UUID) -> Void = { _ in }
    var onSelectHome: () -> Void = {}
    var onSelectPlaylists: () -> Void = {}
    var onSelectLibrary: (PlexLibrary) -> Void = { _ in }
    var onEditServer: (PlexServer) -> Void = { _ in }
    var onRemoveServer: (UUID) -> Void = { _ in }
    var onDismissSidebar: () -> Void = {}
    var activeDownloadCount: Int = 0
    var onSelectAllServersHome: () -> Void = {}
    var onSelectSettings: () -> Void = {}
    var isAggregateHomeSelected: Bool = false

    private var isHomeSelected: Bool {
        selectedLibraryID == nil && !isAggregateHomeSelected
    }

    var body: some View {
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
                        serverButton(server, isReachable: nil, badge: activeDownloadCount)
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
                    isSelected: isAggregateHomeSelected
                ) {
                    onSelectAllServersHome()
                }
            }

            Section("Plex servers") {
                ForEach(plexServers) { server in
                    serverButton(server, isReachable: serverReachable(server.id))
                        .contextMenu {
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
                        Text(librariesLoadError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    ForEach(libraries) { library in
                        rowButton(
                            title: library.title,
                            systemImage: icon(for: library),
                            subtitle: nil,
                            isSelected: selectedLibraryID == library.id
                        ) {
                            onSelectLibrary(library)
                        }
                    }

                    if selectedServer.usesLivePlexAPI, !selectedServer.isDownloadsServer {
                        rowButton(
                            title: "Playlists",
                            systemImage: "music.note.list",
                            subtitle: "Server playlists",
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
                    isSelected: false
                ) {
                    onSelectSettings()
                }
            }
        }
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

    private func serverButton(_ server: PlexServer, isReachable: Bool?, badge: Int = 0) -> some View {
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
                    Text(server.hostDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func rowButton(
        title: String,
        systemImage: String,
        subtitle: String?,
        isSelected: Bool,
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
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
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
