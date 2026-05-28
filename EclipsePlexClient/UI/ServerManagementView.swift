//
//  ServerManagementView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Server admin: sessions, status, users, and library maintenance.
struct ServerManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var registry: PlexServerRegistry
    let server: PlexServer

    @State private var sessions: [PlexActiveSession] = []
    @State private var serverStatus: PlexServerStatusInfo?
    @State private var users: [PlexServerUser] = []
    @State private var isLoadingSessions = false
    @State private var isLoadingStatus = false
    @State private var isLoadingUsers = false
    @State private var sessionsError: String?
    @State private var statusError: String?
    @State private var usersError: String?
    @State private var actionMessage: String?
    @State private var workingLibraryID: String?
    @State private var stoppingSessionId: String?
    @State private var scanConfirmLibrary: PlexLibrary?
    @State private var metadataConfirmLibrary: PlexLibrary?
    @State private var analyzeConfirmLibrary: PlexLibrary?
    @State private var emptyTrashConfirmLibrary: PlexLibrary?
    @State private var sessionToStop: PlexActiveSession?
    @State private var publishToPlex = false
    @State private var relayEnabled = false
    @State private var isUpdatingPublish = false
    @State private var isUpdatingRelay = false
    @State private var sectionToRename: PlexLibrary?
    @State private var sectionToDelete: PlexLibrary?
    @State private var selectedUser: PlexServerUser?

    private var liveServer: PlexServer {
        registry.allServers.first { $0.id == server.id } ?? server
    }

    private var libraries: [PlexLibrary] {
        registry.librariesByServerID[server.id] ?? []
    }

    private var capabilities: PlexServerAdminCapabilities {
        registry.adminCapabilities(for: server.id)
    }

    var body: some View {
        NavigationStack {
            List {
                if let actionMessage {
                    Section {
                        Text(actionMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                serverStatusSection
                sessionsSection

                if capabilities.canManageServer {
                    usersSection
                }

                if capabilities.canManageLibraries {
                    libraryMaintenanceSection
                }
            }
            .navigationTitle("Server management")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") {
                        Task { await reloadAll() }
                    }
                    .disabled(isLoadingSessions || isLoadingStatus)
                }
            }
            .task {
                await registry.refreshAdminCapabilities(for: liveServer)
                await reloadAll()
            }
            .refreshable {
                await reloadAll()
            }
            .confirmDestructive(
                title: "Scan library files?",
                message: scanConfirmMessage,
                confirmLabel: "Scan",
                isPresented: binding(for: $scanConfirmLibrary)
            ) {
                if let library = scanConfirmLibrary {
                    Task { await runLibraryRefresh(library, scanFiles: true) }
                }
            }
            .confirmDestructive(
                title: "Refresh library metadata?",
                message: metadataConfirmMessage,
                confirmLabel: "Refresh",
                isPresented: binding(for: $metadataConfirmLibrary)
            ) {
                if let library = metadataConfirmLibrary {
                    Task { await runLibraryRefresh(library, scanFiles: false) }
                }
            }
            .confirmDestructive(
                title: "Analyze library?",
                message: analyzeConfirmMessage,
                confirmLabel: "Analyze",
                isPresented: binding(for: $analyzeConfirmLibrary)
            ) {
                if let library = analyzeConfirmLibrary {
                    Task { await runSectionAction(library, action: "analyze") }
                }
            }
            .confirmDestructive(
                title: "Empty trash?",
                message: emptyTrashConfirmMessage,
                confirmLabel: "Empty trash",
                isPresented: binding(for: $emptyTrashConfirmLibrary)
            ) {
                if let library = emptyTrashConfirmLibrary {
                    Task { await runSectionAction(library, action: "emptyTrash") }
                }
            }
            .confirmDestructive(
                title: "Stop playback?",
                message: stopSessionMessage,
                confirmLabel: "Stop",
                isPresented: Binding(
                    get: { sessionToStop != nil },
                    set: { if !$0 { sessionToStop = nil } }
                )
            ) {
                if let session = sessionToStop {
                    Task { await stopSession(session) }
                }
            }
            .confirmDestructive(
                title: "Remove library?",
                message: deleteSectionMessage,
                confirmLabel: "Remove",
                isPresented: Binding(
                    get: { sectionToDelete != nil },
                    set: { if !$0 { sectionToDelete = nil } }
                )
            ) {
                if let library = sectionToDelete {
                    Task { await deleteSection(library) }
                }
            }
            .sheet(item: $sectionToRename) { library in
                LibrarySectionRenameSheet(plexServer: liveServer, library: library) {
                    await registry.refreshLibraries(for: liveServer)
                }
            }
            .sheet(item: $selectedUser) { user in
                ServerUserDetailSheet(user: user, libraries: libraries)
            }
        }
#if os(macOS)
        .frame(minWidth: 520, minHeight: 620)
#endif
    }

    // MARK: - Sections

    @ViewBuilder
    private var serverStatusSection: some View {
        Section {
            if isLoadingStatus, serverStatus == nil {
                ProgressView("Loading server status…")
            } else if let statusError {
                Text(statusError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                Button("Retry") { Task { await reloadStatus() } }
            } else if let status = serverStatus {
                if let name = status.friendlyName {
                    labeledRow("Name", name)
                }
                if let version = status.version {
                    labeledRow("Version", version)
                }
                if let platform = status.platform {
                    labeledRow("Platform", platform)
                }
                if let publish = status.publishToPlex {
                    labeledRow("Published to Plex", publish ? "Yes" : "No")
                }
                if let secure = status.secureConnections {
                    labeledRow("Secure connections", secure)
                }
                if let relay = status.relayEnabled {
                    labeledRow("Relay", relay ? "Enabled" : "Disabled")
                }
                if capabilities.canManageServer {
                    Toggle("Publish server to Plex", isOn: $publishToPlex)
                        .disabled(isUpdatingPublish)
                        .onChange(of: publishToPlex) { _, newValue in
                            Task { await updatePublishPref(newValue) }
                        }
                    Toggle("Relay enabled", isOn: $relayEnabled)
                        .disabled(isUpdatingRelay)
                        .onChange(of: relayEnabled) { _, newValue in
                            Task { await updateRelayPref(newValue) }
                        }
                }
            } else {
                Text("No status available.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Server status")
        } footer: {
            Text("Remote access and publishing settings come from the Plex server.")
        }
    }

    @ViewBuilder
    private var sessionsSection: some View {
        Section {
            if isLoadingSessions, sessions.isEmpty {
                ProgressView("Loading active streams…")
            } else if let sessionsError {
                Text(sessionsError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                Button("Retry") { Task { await reloadSessions() } }
            } else if sessions.isEmpty {
                Text("No active streams right now.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions) { session in
                    sessionRow(session)
                }
            }
        } header: {
            Text("Active streams")
        } footer: {
            if !capabilities.canViewSessions {
                Text("Your account may not have permission to view sessions on this server.")
            } else if capabilities.canTerminateSessions {
                Text("Stopping a stream sends a message to the viewer’s client.")
            }
        }
    }

    @ViewBuilder
    private var usersSection: some View {
        Section {
            if isLoadingUsers, users.isEmpty {
                ProgressView("Loading users…")
            } else if let usersError {
                Text(usersError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                Button("Retry") { Task { await reloadUsers() } }
            } else if users.isEmpty {
                Text("No home users returned.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(users) { user in
                    Button {
                        selectedUser = user
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            HStack(spacing: 8) {
                                if user.isAdmin {
                                    Text("Admin")
                                        .font(.caption.weight(.semibold))
                                }
                                if user.isManaged {
                                    Text("Managed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Home users")
        } footer: {
            Text("Invite and permission editing use the Plex web app for full control.")
        }
    }

    @ViewBuilder
    private var libraryMaintenanceSection: some View {
        Section {
            if libraries.isEmpty {
                Text("Load libraries from the server home screen first.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                ForEach(libraries) { library in
                    libraryMaintenanceRow(library)
                }
            }
        } header: {
            Text("Library maintenance")
        } footer: {
            Text("Scan, analyze, and trash operations run on the Plex server and may take a while.")
        }
    }

    // MARK: - Rows

    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func sessionRow(_ session: PlexActiveSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.headline)
                if let subtitle = session.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if let user = session.userName {
                        Label(user, systemImage: "person")
                    }
                    if let player = session.player {
                        Label(player, systemImage: "play.rectangle")
                    }
                    if let state = session.state {
                        Text(state.capitalized)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .labelStyle(.titleAndIcon)
                if let progress = session.progress {
                    ProgressView(value: progress)
                }
            }
            if capabilities.canTerminateSessions {
                Button("Stop stream", role: .destructive) {
                    sessionToStop = session
                }
                .buttonStyle(.pressableBordered)
                .disabled(stoppingSessionId == session.terminateSessionId)
                if stoppingSessionId == session.terminateSessionId {
                    ProgressView()
                        .platformControlSize(.small)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func libraryMaintenanceRow(_ library: PlexLibrary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(library.title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button("Scan files") { scanConfirmLibrary = library }
                    Button("Refresh metadata") { metadataConfirmLibrary = library }
                }
                HStack {
                    Button("Analyze") { analyzeConfirmLibrary = library }
                    Button("Empty trash", role: .destructive) { emptyTrashConfirmLibrary = library }
                }
                if capabilities.canManageServer {
                    HStack {
                        Button("Rename…") { sectionToRename = library }
                        Button("Remove library…", role: .destructive) { sectionToDelete = library }
                    }
                }
            }
            .buttonStyle(.pressableBordered)
            .disabled(workingLibraryID == library.id)
            if workingLibraryID == library.id {
                ProgressView()
                    .platformControlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Confirm messages

    private var scanConfirmMessage: String {
        guard let library = scanConfirmLibrary else { return "" }
        return "Plex will scan files for “\(library.title)”."
    }

    private var metadataConfirmMessage: String {
        guard let library = metadataConfirmLibrary else { return "" }
        return "Plex will refresh metadata for “\(library.title)” without rescanning files."
    }

    private var analyzeConfirmMessage: String {
        guard let library = analyzeConfirmLibrary else { return "" }
        return "Plex will analyze media in “\(library.title)”."
    }

    private var emptyTrashConfirmMessage: String {
        guard let library = emptyTrashConfirmLibrary else { return "" }
        return "Permanently remove trashed items in “\(library.title)”."
    }

    private var stopSessionMessage: String {
        guard let session = sessionToStop else { return "" }
        let user = session.userName ?? "the viewer"
        return "Stop “\(session.title)” for \(user)?"
    }

    private var deleteSectionMessage: String {
        guard let library = sectionToDelete else { return "" }
        return "Remove “\(library.title)” from Plex? Media folders are not deleted from disk."
    }

    private func binding(for library: Binding<PlexLibrary?>) -> Binding<Bool> {
        Binding(
            get: { library.wrappedValue != nil },
            set: { if !$0 { library.wrappedValue = nil } }
        )
    }

    // MARK: - Actions

    @MainActor
    private func reloadAll() async {
        await reloadSessions()
        await reloadStatus()
        if capabilities.canManageServer || liveServer.isOwnedServer == true {
            await reloadUsers()
        }
    }

    @MainActor
    private func reloadSessions() async {
        guard liveServer.usesLivePlexAPI else {
            sessionsError = PlexAPIError.serverNotConfiguredForLiveAPI.adminUserMessage
            return
        }
        isLoadingSessions = true
        sessionsError = nil
        defer { isLoadingSessions = false }
        do {
            let client = try PlexMediaServerClient(server: liveServer)
            sessions = try await client.fetchActiveSessions()
        } catch {
            sessions = []
            sessionsError = PlexAPIError.from(error)
        }
    }

    @MainActor
    private func reloadStatus() async {
        guard liveServer.usesLivePlexAPI else { return }
        isLoadingStatus = true
        statusError = nil
        defer { isLoadingStatus = false }
        do {
            let client = try PlexMediaServerClient(server: liveServer)
            let status = try await client.fetchServerStatus()
            serverStatus = status
            if let publish = status.publishToPlex {
                publishToPlex = publish
            }
            if let relay = status.relayEnabled {
                relayEnabled = relay
            }
        } catch {
            serverStatus = nil
            statusError = PlexAPIError.from(error)
        }
    }

    @MainActor
    private func reloadUsers() async {
        guard liveServer.usesLivePlexAPI, capabilities.canManageServer else { return }
        isLoadingUsers = true
        usersError = nil
        defer { isLoadingUsers = false }
        do {
            let client = try PlexMediaServerClient(server: liveServer)
            users = try await client.fetchServerUsers()
        } catch {
            users = []
            usersError = PlexAPIError.from(error)
        }
    }

    @MainActor
    private func stopSession(_ session: PlexActiveSession) async {
        stoppingSessionId = session.terminateSessionId
        actionMessage = nil
        defer {
            stoppingSessionId = nil
            sessionToStop = nil
        }
        do {
            let client = try PlexMediaServerClient(server: liveServer)
            try await client.terminateSession(sessionId: session.terminateSessionId)
            PlexAdminActionLog.record(
                serverName: liveServer.name,
                action: "stop session",
                success: true,
                detail: session.title
            )
            actionMessage = "Stopped stream for \(session.title)."
            await reloadSessions()
        } catch {
            let message = PlexAPIError.from(error)
            actionMessage = message
            PlexAdminActionLog.record(
                serverName: liveServer.name,
                action: "stop session",
                success: false,
                detail: message
            )
        }
    }

    @MainActor
    private func updateRelayPref(_ enabled: Bool) async {
        isUpdatingRelay = true
        defer { isUpdatingRelay = false }
        do {
            let client = try PlexMediaServerClient(server: liveServer)
            try await client.updateServerPref(id: "RelayEnabled", value: enabled ? "1" : "0")
            PlexAdminActionLog.record(
                serverName: liveServer.name,
                action: "relay pref",
                success: true,
                detail: enabled ? "on" : "off"
            )
            await reloadStatus()
        } catch {
            actionMessage = PlexAdminCompatibility.message(for: error, action: "relay settings")
            relayEnabled = !enabled
        }
    }

    @MainActor
    private func updatePublishPref(_ enabled: Bool) async {
        isUpdatingPublish = true
        defer { isUpdatingPublish = false }
        do {
            let client = try PlexMediaServerClient(server: liveServer)
            try await client.updateServerPref(id: "PublishServerOnPlex", value: enabled ? "1" : "0")
            PlexAdminActionLog.record(
                serverName: liveServer.name,
                action: "publish pref",
                success: true,
                detail: enabled ? "on" : "off"
            )
            await reloadStatus()
        } catch {
            actionMessage = PlexAPIError.from(error)
            publishToPlex = !enabled
        }
    }

    @MainActor
    private func runLibraryRefresh(_ library: PlexLibrary, scanFiles: Bool) async {
        workingLibraryID = library.id
        actionMessage = nil
        defer { workingLibraryID = nil }
        do {
            let client = try PlexMediaServerClient(server: liveServer)
            try await client.refreshLibrarySection(sectionID: library.sectionID, scanFiles: scanFiles)
            let action = scanFiles ? "scan library" : "refresh library metadata"
            PlexAdminActionLog.record(serverName: liveServer.name, action: action, success: true, detail: library.title)
            actionMessage = scanFiles
                ? "Scan started for \(library.title)."
                : "Metadata refresh started for \(library.title)."
        } catch {
            actionMessage = PlexAPIError.from(error)
        }
    }

    @MainActor
    private func runSectionAction(_ library: PlexLibrary, action: String) async {
        workingLibraryID = library.id
        actionMessage = nil
        defer { workingLibraryID = nil }
        do {
            let client = try PlexMediaServerClient(server: liveServer)
            switch action {
            case "analyze":
                try await client.analyzeLibrarySection(sectionID: library.sectionID)
                actionMessage = "Analyze started for \(library.title)."
            case "emptyTrash":
                try await client.emptyLibraryTrash(sectionID: library.sectionID)
                actionMessage = "Trash emptied for \(library.title)."
            default:
                break
            }
            PlexAdminActionLog.record(
                serverName: liveServer.name,
                action: action,
                success: true,
                detail: library.title
            )
        } catch {
            let message = PlexAdminCompatibility.message(for: error, action: action)
            actionMessage = message
            PlexAdminActionLog.record(
                serverName: liveServer.name,
                action: action,
                success: false,
                detail: message
            )
        }
    }

    @MainActor
    private func deleteSection(_ library: PlexLibrary) async {
        workingLibraryID = library.id
        actionMessage = nil
        defer {
            workingLibraryID = nil
            sectionToDelete = nil
        }
        do {
            let client = try PlexMediaServerClient(server: liveServer)
            try await client.deleteLibrarySection(sectionID: library.sectionID)
            PlexAdminActionLog.record(
                serverName: liveServer.name,
                action: "delete library",
                success: true,
                detail: library.title
            )
            actionMessage = "Removed \(library.title)."
            await registry.refreshLibraries(for: liveServer)
        } catch {
            actionMessage = PlexAdminCompatibility.message(for: error, action: "removing a library section")
        }
    }
}
