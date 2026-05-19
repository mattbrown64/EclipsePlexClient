//
//  AddPlexServerSheet.swift
//  EclipsePlexClient
//

import SwiftUI

private enum AddServerMode: String, CaseIterable, Identifiable {
    case account = "Plex account"
    case manual = "Manual"

    var id: String { rawValue }
}

/// Add a Plex Media Server manually or sign in to Plex to list servers on your account.
struct AddPlexServerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @ObservedObject var registry: PlexServerRegistry
    /// Called with new server when added successfully (e.g. to select it in the shell).
    var onAdded: ((PlexServer) -> Void)?

    @State private var mode: AddServerMode = .account

    @State private var host = ""
    @State private var token = ""
    @State private var customName = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    @State private var accountServers: [PlexServer] = []
    @State private var isSigningIn = false
    @State private var isLoadingAccountServers = false
    @State private var signInTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Add via", selection: $mode) {
                        ForEach(AddServerMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .account {
                    accountSection
                } else {
                    manualSection
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Add Plex Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isWorking || isSigningIn)
                }
            }
            .onDisappear {
                signInTask?.cancel()
            }
            .task(id: "\(mode)|\(registry.plexAccountAuthToken ?? "")") {
                guard mode == .account else { return }
                guard let t = registry.plexAccountAuthToken, !t.isEmpty else {
                    accountServers = []
                    return
                }
                await refreshAccountServerList(accountToken: t)
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: mode == .account ? 420 : 300)
        #endif
    }

    @ViewBuilder
    private var accountSection: some View {
        Section {
            Text("Sign in with your Plex account to see Media Servers you can reach (home, shared, and remote).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if let tok = registry.plexAccountAuthToken, !tok.isEmpty {
            Section("Signed in") {
                HStack {
                    Button("Refresh server list") {
                        Task { await refreshAccountServerList(accountToken: tok) }
                    }
                    .disabled(isLoadingAccountServers || isSigningIn)
                    Spacer()
                    Button("Sign out") {
                        registry.setPlexAccountToken(nil)
                        accountServers = []
                    }
                    .disabled(isSigningIn)
                }
                if isLoadingAccountServers {
                    HStack {
                        ProgressView()
                        Text("Loading…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        Section {
            Button {
                signInTask?.cancel()
                signInTask = Task { await runPlexPinSignIn() }
            } label: {
                if isSigningIn {
                    Label("Waiting for browser sign-in…", systemImage: "hourglass")
                } else {
                    Label("Sign in with Plex", systemImage: "person.badge.key")
                }
            }
            .disabled(isSigningIn || isLoadingAccountServers)
            if isSigningIn {
                Text("Complete sign-in in the page that opened, then return here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        if !accountServers.isEmpty {
            Section("Servers on your account") {
                ForEach(accountServers) { server in
                    Button {
                        Task { await addVerifiedServer(server) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(server.name)
                                .foregroundStyle(.primary)
                            Text(server.hostDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .disabled(isWorking)
                }
            }
        } else if !isLoadingAccountServers, registry.plexAccountAuthToken != nil, !isSigningIn {
            Section {
                Text("No servers returned. Try Refresh, or add a server manually.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var manualSection: some View {
        Section {
            TextField("Address", text: $host, prompt: Text("192.168.1.10:32400 or https://plex.example.com"))
                .textContentType(.URL)
#if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
#endif
            SecureField("Plex token (X-Plex-Token)", text: $token)
            TextField("Display name (optional)", text: $customName)
        } footer: {
            Text("Use a Plex token from an account that can access this server.")
                .font(.footnote)
        }
        Section {
            Button("Add") {
                Task { await connectManualAndAdd() }
            }
            .disabled(
                isWorking
                    || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
    }

    private func refreshAccountServerList(accountToken: String) async {
        isLoadingAccountServers = true
        errorMessage = nil
        defer { isLoadingAccountServers = false }
        do {
            accountServers = try await PlexAccountAPI.fetchMediaServers(accountToken: accountToken)
            if accountServers.isEmpty {
                errorMessage =
                    "No Media Servers responded from this device. Plex often advertises URLs that only work on certain networks (for example addresses ending in .plex.direct). Try Manual with your server’s LAN IP and port (for example 192.168.1.10:32400), or check Wi‑Fi, VPN, and Local Network permission."
            }
        } catch {
            errorMessage = error.localizedDescription
            accountServers = []
        }
    }

    private func runPlexPinSignIn() async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            let pin = try await PlexAccountAPI.createPin()
            let cid = PlexHTTPConstants.clientIdentifier
            guard let authURL = PlexAccountAPI.plexAuthPageURL(clientIdentifier: cid, pinCode: pin.code) else {
                errorMessage = "Could not build Plex sign-in URL."
                return
            }
            openURL(authURL)
            let accountToken = try await PlexAccountAPI.pollForAccountToken(pinId: pin.id)
            registry.setPlexAccountToken(accountToken)
            accountServers = try await PlexAccountAPI.fetchMediaServers(accountToken: accountToken)
        } catch is CancellationError {
            // dismissed or cancelled
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addVerifiedServer(_ server: PlexServer) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let client = try PlexMediaServerClient(server: server)
            try await client.verifyReachable()
            registry.addCustomServer(server)
            onAdded?(server)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func connectManualAndAdd() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let hostTrim = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenTrim = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostTrim.isEmpty, !tokenTrim.isEmpty else {
            errorMessage = "Enter both an address and a token."
            return
        }

        var server = PlexServer(
            name: customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Plex Server" : customName,
            hostDescription: hostTrim,
            accessToken: tokenTrim
        )
        guard server.usesLivePlexAPI else {
            errorMessage = "Could not parse the server address."
            return
        }

        do {
            let tmp = server
            let client = try PlexMediaServerClient(server: tmp)
            try await client.verifyReachable()
            let friendly = try await client.fetchFriendlyName()
            if customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                server.name = friendly
            }
            registry.addCustomServer(server)
            onAdded?(server)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
