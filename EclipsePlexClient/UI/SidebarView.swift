//
//  SidebarView.swift
//  EclipsePlexClient
//
//  Created by Matt Brown on 5/15/26.
//

import SwiftUI

/// First column of `NavigationSplitView`: choose Plex server and library.
struct SidebarView: View {
    let plexServers: [PlexServer]
    @Binding var selectedPlexServerID: UUID?
    let librariesForSelectedServer: [PlexLibrary]
    @Binding var selectedPlexLibraryID: String?

    var isLoadingLibraries = false
    var librariesLoadError: String?
    var librariesErrorServerID: UUID?
    var selectedServerID: UUID?
    var isUserAddedServer: (UUID) -> Bool = { _ in false }
    var onRemoveServer: (UUID) -> Void = { _ in }

    @EnvironmentObject private var sidebarInteraction: SidebarInteractionState

    var body: some View {
        NavigationStack {
            List {
                Section("Plex servers") {
                    ForEach(plexServers) { server in
                        sidebarRow(
                            title: server.name,
                            subtitle: server.hostDescription,
                            isSelected: selectedPlexServerID == server.id
                        ) {
                            selectedPlexServerID = server.id
                        }
                        .contextMenu {
                            if isUserAddedServer(server.id) {
                                Button("Remove Server", role: .destructive) {
                                    onRemoveServer(server.id)
                                }
                            }
                        }
                    }
                }
                if isLoadingLibraries {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Loading libraries…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let err = librariesLoadError,
                   let errSid = librariesErrorServerID, errSid == selectedServerID {
                    Section {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                if !librariesForSelectedServer.isEmpty {
                    Section("Libraries for this server") {
                        ForEach(librariesForSelectedServer) { library in
                            sidebarRow(
                                title: library.title,
                                subtitle: nil,
                                isSelected: selectedPlexLibraryID == library.id
                            ) {
                                if selectedPlexLibraryID == library.id {
                                    selectedPlexLibraryID = nil
                                } else {
                                    selectedPlexLibraryID = library.id
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Eclipse Plex")
        }
        .disabled(sidebarInteraction.suppressSidebarInteraction)
    }

    private func sidebarRow(
        title: String,
        subtitle: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationSplitView {
        SidebarView(
            plexServers: PlexSampleData.servers,
            selectedPlexServerID: .constant(PlexSampleData.servers.first?.id),
            librariesForSelectedServer: PlexSampleData.libraries(for: PlexSampleData.servers[0].id),
            selectedPlexLibraryID: .constant(
                PlexSampleData.libraries(for: PlexSampleData.servers[0].id).first?.id
            )
        )
    } detail: {
        Text("Detail preview")
    }
    .environmentObject(SidebarInteractionState())
}
