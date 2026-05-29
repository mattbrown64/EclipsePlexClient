//
//  SettingsServersSection.swift
//  EclipsePlexClient
//

import SwiftUI

/// Per-server health, token status, and maintenance actions in Settings.
struct SettingsServersSection: View {
    @ObservedObject var registry: PlexServerRegistry

    @State private var serverToEdit: PlexServer?
    @State private var connectionPickerServer: PlexServer?
    @State private var serverManagementServer: PlexServer?
    @State private var serverToRemove: PlexServer?
    @State private var testingServerID: UUID?
    @State private var showPlexSignIn = false

    private var plexServers: [PlexServer] {
        registry.allServers.filter { !$0.isDownloadsServer }
    }

    var body: some View {
        Section {
            if plexServers.isEmpty {
                Text("No Plex servers added yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(plexServers) { server in
                    serverRow(server)
                }
            }
        } header: {
            Text("Servers")
        } footer: {
            Text("Token and reachability status for each saved server. Test connection refreshes libraries and probes the server.")
        }
        .sheet(item: $serverToEdit) { server in
            EditPlexServerSheet(registry: registry, server: server)
        }
        .sheet(item: $connectionPickerServer) { server in
            ServerConnectionPickerSheet(server: server, registry: registry)
        }
        .sheet(item: $serverManagementServer) { server in
            ServerManagementView(registry: registry, server: server)
        }
        .sheet(isPresented: $showPlexSignIn) {
            AddPlexServerSheet(registry: registry) { _ in
                Task {
                    for server in registry.allServers where !server.isDownloadsServer {
                        _ = await registry.refreshDiscoveredServerConnection(serverId: server.id)
                        registry.scheduleRefreshLibraries(for: server, force: true)
                    }
                }
            }
        }
        .confirmDestructive(
            title: "Remove server?",
            message: serverToRemove.map { "Remove \($0.name) from this device? Tokens and cached libraries for this server are cleared." } ?? "",
            confirmLabel: "Remove",
            isPresented: Binding(
                get: { serverToRemove != nil },
                set: { if !$0 { serverToRemove = nil } }
            )
        ) {
            if let server = serverToRemove {
                registry.removeCustomServer(id: server.id)
            }
            serverToRemove = nil
        }
    }

    @ViewBuilder
    private func serverRow(_ server: PlexServer) -> some View {
        let issue = registry.connectionIssue(for: server)
        let reachable = registry.serverReachable[server.id]
        let tokenPresent = !(KeychainStore.token(forServerID: server.id)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        let isTesting = testingServerID == server.id

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                if let color = statusColor(issue: issue, reachable: reachable) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.headline)
                    if let issue {
                        Text(issue.title)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if reachable == true {
                        Text("Connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(subtitle(for: server, issue: issue, reachable: reachable, tokenPresent: tokenPresent))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 12) {
                if issue == .missingToken {
                    Button {
                        showPlexSignIn = true
                    } label: {
                        Label("Sign in to Plex", systemImage: "person.badge.key")
                    }
                }
                Button("Edit") { serverToEdit = server }
                Button("Test") {
                    testConnection(server)
                }
                .disabled(isTesting)
                if server.connectionCandidates.count > 1 {
                    Button("Connection") {
                        connectionPickerServer = server
                    }
                }
                if registry.adminCapabilities(for: server.id).canManageServer, server.usesLivePlexAPI {
                    Button("Manage") {
                        serverManagementServer = server
                    }
                }
                Button("Remove", role: .destructive) {
                    serverToRemove = server
                }
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func subtitle(
        for server: PlexServer,
        issue: PlexServerConnectionIssue?,
        reachable: Bool?,
        tokenPresent: Bool
    ) -> String {
        var parts: [String] = []
        parts.append(tokenPresent ? "Token configured" : "No token")
        if let active = server.withActiveConnection().plexOriginURL?.host {
            parts.append(active)
        } else {
            parts.append(server.hostDescription)
        }
        if issue == .offline, let last = registry.lastOnlineAt(for: server.id) {
            let rel = RelativeDateTimeFormatter().localizedString(for: last, relativeTo: Date())
            parts.append("Last online \(rel)")
        }
        return parts.joined(separator: " · ")
    }

    private func statusColor(issue: PlexServerConnectionIssue?, reachable: Bool?) -> Color? {
        if let issue {
            switch issue {
            case .missingToken, .invalidAddress, .librariesFailed:
                return .orange
            case .offline:
                return .red
            }
        }
        if let reachable {
            return reachable ? .green : .red
        }
        return nil
    }

    private func testConnection(_ server: PlexServer) {
        testingServerID = server.id
        Task {
            await registry.refreshReachability(for: server.withTokenFromKeychain().withActiveConnection(), force: true)
            registry.scheduleRefreshLibraries(for: server, force: true)
            testingServerID = nil
        }
    }
}
