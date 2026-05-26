//
//  ServerUserDetailSheet.swift
//  EclipsePlexClient
//

import SwiftUI

/// Home-user details and library access overview (full invite/edit remains on Plex web).
struct ServerUserDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let user: PlexServerUser
    let libraries: [PlexLibrary]

    private static let plexHomeUsersURL = URL(string: "https://app.plex.tv/desktop#!/settings/plex/home")!

    var body: some View {
        NavigationStack {
            List {
                Section("User") {
                    Text(user.title)
                        .font(.headline)
                    if user.isAdmin {
                        Label("Server admin", systemImage: "checkmark.shield")
                    }
                    if user.isManaged {
                        Label("Managed account", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }

                Section {
                    if libraries.isEmpty {
                        Text("No libraries loaded for this server yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(libraries) { library in
                            Text(library.title)
                        }
                    }
                } header: {
                    Text("Libraries on this server")
                } footer: {
                    Text("Per-user library restrictions and invites are managed in the Plex web app.")
                }

                Section {
                    Button("Open Plex home users…") {
                        openURL(Self.plexHomeUsersURL)
                    }
                }
            }
            .navigationTitle("User access")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 400, minHeight: 360)
#endif
    }
}
