//
//  ServerConnectionPickerSheet.swift
//  EclipsePlexClient
//

import SwiftUI

/// Lets the user pick among discovered Plex server URLs (LAN vs relay).
struct ServerConnectionPickerSheet: View {
    let server: PlexServer
    @ObservedObject var registry: PlexServerRegistry
    @Environment(\.dismiss) private var dismiss

    private var candidates: [String] {
        let stored = server.connectionCandidates
        if stored.isEmpty {
            return [server.hostDescription]
        }
        return stored
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(candidates, id: \.self) { url in
                    Button {
                        PlexServerConnectionStore.setActiveHost(url, for: server.id)
                        if var updated = registry.allServers.first(where: { $0.id == server.id }) {
                            updated.hostDescription = url
                            registry.updateCustomServer(updated)
                        }
                        Task { await registry.refreshReachability(for: server.withActiveConnection()) }
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(connectionLabel(url))
                                    .font(.body)
                                Text(url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if server.activeHostDescription == url {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.pressablePlain)
                }
            }
            .navigationTitle("Connection")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func connectionLabel(_ url: String) -> String {
        let lower = url.lowercased()
        if lower.contains("192.168.") || lower.contains("10.") || lower.contains("127.0.0.1") {
            return "Local network"
        }
        if lower.contains("plex.direct") { return "Plex Direct" }
        if lower.contains("relay") { return "Relay" }
        return "Remote"
    }
}
