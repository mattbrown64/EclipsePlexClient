//
//  LibrarySectionRenameSheet.swift
//  EclipsePlexClient
//

import SwiftUI

/// Rename a Plex library section (`PUT /library/sections/{id}`).
struct LibrarySectionRenameSheet: View {
    @Environment(\.dismiss) private var dismiss

    let plexServer: PlexServer
    let library: PlexLibrary
    var onRenamed: () async -> Void = {}

    @State private var title: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        plexServer: PlexServer,
        library: PlexLibrary,
        onRenamed: @escaping () async -> Void = {}
    ) {
        self.plexServer = plexServer
        self.library = library
        self.onRenamed = onRenamed
        _title = State(initialValue: library.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
                Section("Library name") {
                    TextField("Title", text: $title)
                }
            }
            .navigationTitle("Rename library")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 360, minHeight: 200)
#endif
    }

    @MainActor
    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let client = try PlexMediaServerClient(server: plexServer)
            try await client.updateLibrarySectionTitle(sectionID: library.sectionID, title: title)
            PlexAdminActionLog.record(
                serverName: plexServer.name,
                action: "rename library",
                success: true,
                detail: title
            )
            dismiss()
            await onRenamed()
        } catch {
            errorMessage = PlexAPIError.from(error)
            PlexAdminActionLog.record(
                serverName: plexServer.name,
                action: "rename library",
                success: false,
                detail: PlexAPIError.from(error)
            )
        }
    }
}
