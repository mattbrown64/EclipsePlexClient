//
//  EditPlexServerSheet.swift
//  EclipsePlexClient
//

import SwiftUI

/// Edit an existing Plex server connection (name, URL, token).
struct EditPlexServerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var registry: PlexServerRegistry
    let server: PlexServer

    @State private var name: String
    @State private var host: String
    @State private var token: String
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showConnectionPicker = false

    init(registry: PlexServerRegistry, server: PlexServer) {
        self.registry = registry
        self.server = server
        _name = State(initialValue: server.name)
        _host = State(initialValue: server.hostDescription)
        _token = State(initialValue: KeychainStore.token(forServerID: server.id) ?? server.accessToken ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Name", text: $name)
                    TextField("URL (https://host:32400)", text: $host)
                    SecureField("Plex token", text: $token)
                    if server.connectionCandidates.count > 1 {
                        Button("Choose connection…") {
                            showConnectionPicker = true
                        }
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Edit Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isWorking || host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 220)
        #endif
        .sheet(isPresented: $showConnectionPicker) {
            ServerConnectionPickerSheet(server: server, registry: registry)
        }
    }

    @MainActor
    private func save() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        var updated = server
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.accessToken = trimmedToken.isEmpty ? nil : trimmedToken

        do {
            let validatedHost = try PlexNetworkPolicy.validateHostDescription(host)
            updated.hostDescription = validatedHost
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        do {
            let probe = PlexServer(
                id: updated.id,
                name: updated.name,
                hostDescription: updated.hostDescription,
                accessToken: updated.accessToken,
                plexResourceClientIdentifier: updated.plexResourceClientIdentifier
            )
            let client = try PlexMediaServerClient(server: probe)
            try await client.verifyReachable()
            registry.updateCustomServer(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
