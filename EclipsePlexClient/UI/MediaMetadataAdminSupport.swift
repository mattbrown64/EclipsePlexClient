//
//  MediaMetadataAdminSupport.swift
//  EclipsePlexClient
//

import SwiftUI

/// Shared state for metadata admin sheets and confirmations on a single screen.
struct MediaMetadataAdminState {
    var showFixMatch = false
    var showEditMetadata = false
    var showRefreshConfirm = false
    var showDeleteConfirm = false
    var showOptimizeConfirm = false
    var isWorking = false
    var statusMessage: String?
}

enum MediaMetadataAdminAccess {
    static func isEligible(plexServer: PlexServer, node: PlexCatalogNode? = nil) -> Bool {
        guard plexServer.usesLivePlexAPI, !plexServer.isDownloadsServer else { return false }
        guard let node else { return true }
        return node.supportsMetadataAdmin
    }

    static func canManage(
        plexServer: PlexServer,
        registry: PlexServerRegistry
    ) -> Bool {
        isEligible(plexServer: plexServer)
            && registry.adminCapabilities(for: plexServer.id).canManageLibraries
    }

    /// Whether to attach a context menu before capabilities finish probing.
    static func shouldOfferContextMenu(
        plexServer: PlexServer,
        registry: PlexServerRegistry,
        node: PlexCatalogNode? = nil
    ) -> Bool {
        guard isEligible(plexServer: plexServer, node: node) else { return false }
        let caps = registry.adminCapabilities(for: plexServer.id)
        if caps.canManageLibraries { return true }
        return caps == .unknown
    }

    static func refreshCapabilitiesIfNeeded(
        plexServer: PlexServer,
        registry: PlexServerRegistry
    ) async {
        guard isEligible(plexServer: plexServer),
              registry.adminCapabilities(for: plexServer.id) == .unknown else { return }
        await registry.refreshAdminCapabilities(for: plexServer)
    }
}

// MARK: - Menu content

@ViewBuilder
func mediaMetadataAdminMenuButtons(
    plexServer: PlexServer,
    ratingKey: String,
    showFixMatch: Binding<Bool>,
    showEditMetadata: Binding<Bool>,
    showRefreshConfirm: Binding<Bool>,
    showDeleteConfirm: Binding<Bool>,
    showOptimizeConfirm: Binding<Bool>,
    isWorking: Bool
) -> some View {
    let plexWebURL = plexServer.plexWebMetadataURL(ratingKey: ratingKey)
    let localWebURL = plexServer.localWebMetadataURL(ratingKey: ratingKey)

    Button("Edit metadata…") {
        showEditMetadata.wrappedValue = true
    }
    .disabled(isWorking)
    Button("Fix match…") {
        showFixMatch.wrappedValue = true
    }
    .disabled(isWorking)

    Divider()

    Button("Refresh metadata") {
        showRefreshConfirm.wrappedValue = true
    }
    .disabled(isWorking)
    Button("Optimize") {
        showOptimizeConfirm.wrappedValue = true
    }
    .disabled(isWorking)

    if plexWebURL != nil || localWebURL != nil {
        Divider()
        if let plexWebURL {
            Link("Open in Plex Web", destination: plexWebURL)
        }
        if let localWebURL {
            Link("Open on server", destination: localWebURL)
        }
    }

    Divider()

    Button("Delete from library", role: .destructive) {
        showDeleteConfirm.wrappedValue = true
    }
    .disabled(isWorking)
}

/// Metadata actions menu for detail screens (all platforms).
@ViewBuilder
func mediaMetadataAdminActionsMenu(
    plexServer: PlexServer,
    ratingKey: String,
    showFixMatch: Binding<Bool>,
    showEditMetadata: Binding<Bool>,
    showRefreshConfirm: Binding<Bool>,
    showDeleteConfirm: Binding<Bool>,
    showOptimizeConfirm: Binding<Bool>,
    isWorking: Bool,
    isEnabled: Bool
) -> some View {
    Menu {
        mediaMetadataAdminMenuButtons(
            plexServer: plexServer,
            ratingKey: ratingKey,
            showFixMatch: showFixMatch,
            showEditMetadata: showEditMetadata,
            showRefreshConfirm: showRefreshConfirm,
            showDeleteConfirm: showDeleteConfirm,
            showOptimizeConfirm: showOptimizeConfirm,
            isWorking: isWorking
        )
    } label: {
        Label("Metadata actions", systemImage: "slider.horizontal.3")
    }
    .disabled(isWorking || !isEnabled)
}

// MARK: - Modifier

struct MediaMetadataAdminModifier: ViewModifier {
    let plexServer: PlexServer
    let ratingKey: String
    let title: String
    let summary: String?
    let year: Int?
    var showTitle: String? = nil
    var seasonTitle: String? = nil
    var sectionType: PlexSectionType? = nil
    var includesPresentation: Bool = true
    var includesContextMenu: Bool = false
    var onMetadataUpdated: () async -> Void = {}
    var onItemDeleted: () async -> Void = {}

    @Binding var state: MediaMetadataAdminState
    @EnvironmentObject private var registry: PlexServerRegistry

    private var canManage: Bool {
        MediaMetadataAdminAccess.canManage(plexServer: plexServer, registry: registry)
    }

    private var offersContextMenu: Bool {
        includesContextMenu
            && MediaMetadataAdminAccess.shouldOfferContextMenu(
                plexServer: plexServer,
                registry: registry
            )
    }

    func body(content: Content) -> some View {
        Group {
            if offersContextMenu {
                content
                    .contentShape(Rectangle())
                    .contextMenu {
                        if canManage {
                            mediaMetadataAdminMenuButtons(
                                plexServer: plexServer,
                                ratingKey: ratingKey,
                                showFixMatch: $state.showFixMatch,
                                showEditMetadata: $state.showEditMetadata,
                                showRefreshConfirm: $state.showRefreshConfirm,
                                showDeleteConfirm: $state.showDeleteConfirm,
                                showOptimizeConfirm: $state.showOptimizeConfirm,
                                isWorking: state.isWorking
                            )
                        }
                    }
            } else {
                content
            }
        }
        .modifier(
            MediaMetadataAdminPresentationModifier(
                plexServer: plexServer,
                ratingKey: ratingKey,
                title: title,
                summary: summary,
                year: year,
                showTitle: showTitle,
                seasonTitle: seasonTitle,
                sectionType: sectionType,
                isEnabled: includesPresentation && canManage,
                state: $state,
                onMetadataUpdated: onMetadataUpdated,
                onItemDeleted: onItemDeleted
            )
        )
        .task {
            await MediaMetadataAdminAccess.refreshCapabilitiesIfNeeded(
                plexServer: plexServer,
                registry: registry
            )
        }
    }
}

private struct MediaMetadataAdminPresentationModifier: ViewModifier {
    let plexServer: PlexServer
    let ratingKey: String
    let title: String
    let summary: String?
    let year: Int?
    var showTitle: String?
    var seasonTitle: String?
    var sectionType: PlexSectionType?
    let isEnabled: Bool
    @Binding var state: MediaMetadataAdminState
    var onMetadataUpdated: () async -> Void
    var onItemDeleted: () async -> Void = {}

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .sheet(isPresented: $state.showFixMatch) {
                    FixMatchPickerSheet(
                        plexServer: plexServer,
                        ratingKey: ratingKey,
                        title: title,
                        year: year,
                        showTitle: showTitle,
                        seasonTitle: seasonTitle,
                        sectionType: sectionType
                    ) {
                        await onMetadataUpdated()
                    }
                }
                .sheet(isPresented: $state.showEditMetadata) {
                    EditMetadataSheet(
                        plexServer: plexServer,
                        ratingKey: ratingKey,
                        initialTitle: title,
                        initialSummary: summary,
                        initialYear: year
                    ) {
                        await onMetadataUpdated()
                    }
                }
                .confirmDestructive(
                    title: "Refresh metadata?",
                    message: "Plex will refresh metadata for “\(title)” from online sources.",
                    confirmLabel: "Refresh",
                    isPresented: $state.showRefreshConfirm
                ) {
                    Task { await refreshMetadata() }
                }
                .confirmDestructive(
                    title: "Optimize files?",
                    message: "Plex may replace this item with an optimized copy. This can take a long time.",
                    confirmLabel: "Optimize",
                    isPresented: $state.showOptimizeConfirm
                ) {
                    Task { await optimizeMetadata() }
                }
                .confirmDestructive(
                    title: "Delete from library?",
                    message: "Remove “\(title)” from the Plex library. Files may remain on disk depending on server settings.",
                    confirmLabel: "Delete",
                    isPresented: $state.showDeleteConfirm
                ) {
                    Task { await deleteMetadata() }
                }
        } else {
            content
        }
    }

    @MainActor
    private func refreshMetadata() async {
        await runAction("refresh metadata") {
            let client = try PlexMediaServerClient(server: plexServer)
            try await client.refreshItemMetadata(ratingKey: ratingKey)
            state.statusMessage = "Metadata refresh started."
            AppToastCenter.show("Refreshing metadata for \(title)")
            await onMetadataUpdated()
        }
    }

    @MainActor
    private func optimizeMetadata() async {
        await runAction("optimize metadata") {
            let client = try PlexMediaServerClient(server: plexServer)
            try await client.optimizeItemMetadata(ratingKey: ratingKey)
            state.statusMessage = "Optimize started."
            AppToastCenter.show("Optimizing \(title)")
            await onMetadataUpdated()
        }
    }

    @MainActor
    private func deleteMetadata() async {
        await runAction("delete metadata") {
            let client = try PlexMediaServerClient(server: plexServer)
            try await client.deleteItemMetadata(ratingKey: ratingKey)
            AppToastCenter.show("Deleted \(title)")
            await onItemDeleted()
        }
    }

    @MainActor
    private func runAction(_ action: String, _ work: () async throws -> Void) async {
        state.isWorking = true
        state.statusMessage = nil
        defer { state.isWorking = false }
        do {
            try await work()
            PlexAdminActionLog.record(serverName: plexServer.name, action: action, success: true, detail: title)
        } catch {
            let message = PlexAPIError.from(error)
            state.statusMessage = message
            PlexAdminActionLog.record(serverName: plexServer.name, action: action, success: false, detail: message)
        }
    }
}

extension View {
    func mediaMetadataAdmin(
        plexServer: PlexServer,
        ratingKey: String,
        title: String,
        summary: String? = nil,
        year: Int?,
        state: Binding<MediaMetadataAdminState>,
        showTitle: String? = nil,
        seasonTitle: String? = nil,
        sectionType: PlexSectionType? = nil,
        includesPresentation: Bool = true,
        includesContextMenu: Bool = false,
        onMetadataUpdated: @escaping () async -> Void = {},
        onItemDeleted: @escaping () async -> Void = {}
    ) -> some View {
        modifier(
            MediaMetadataAdminModifier(
                plexServer: plexServer,
                ratingKey: ratingKey,
                title: title,
                summary: summary,
                year: year,
                showTitle: showTitle,
                seasonTitle: seasonTitle,
                sectionType: sectionType,
                includesPresentation: includesPresentation,
                includesContextMenu: includesContextMenu,
                onMetadataUpdated: onMetadataUpdated,
                onItemDeleted: onItemDeleted,
                state: state
            )
        )
    }

    /// Context menu on catalog row/grid **label content** (must be inside `NavigationLink` label on iOS).
    func catalogMetadataAdminContextMenu<ExtraMenu: View>(
        plexServer: PlexServer,
        node: PlexCatalogNode,
        sectionType: PlexSectionType? = nil,
        @ViewBuilder extraMenu: @escaping () -> ExtraMenu = { EmptyView() }
    ) -> some View {
        modifier(
            CatalogMetadataAdminMenuModifier(
                plexServer: plexServer,
                node: node,
                sectionType: sectionType,
                extraMenu: extraMenu
            )
        )
    }

    @available(*, deprecated, message: "Apply catalogMetadataAdminContextMenu to the NavigationLink label instead.")
    func catalogMetadataAdminMenu<ExtraMenu: View>(
        plexServer: PlexServer,
        node: PlexCatalogNode,
        @ViewBuilder extraMenu: @escaping () -> ExtraMenu = { EmptyView() }
    ) -> some View {
        catalogMetadataAdminContextMenu(plexServer: plexServer, node: node, extraMenu: extraMenu)
    }
}

private struct CatalogMetadataAdminMenuModifier<ExtraMenu: View>: ViewModifier {
    let plexServer: PlexServer
    let node: PlexCatalogNode
    var sectionType: PlexSectionType?
    let extraMenu: () -> ExtraMenu

    private var fixMatchShowTitle: String? {
        if case .episode(let episode) = node { return episode.showTitle }
        return nil
    }

    private var fixMatchSeasonTitle: String? {
        if case .episode(let episode) = node { return "Season \(episode.seasonNumber)" }
        return nil
    }

    @EnvironmentObject private var registry: PlexServerRegistry
    @State private var state = MediaMetadataAdminState()

    private var ratingKey: String? { node.metadataAdminRatingKey }

    private var canManage: Bool {
        MediaMetadataAdminAccess.canManage(plexServer: plexServer, registry: registry)
    }

    private var offersContextMenu: Bool {
        MediaMetadataAdminAccess.shouldOfferContextMenu(
            plexServer: plexServer,
            registry: registry,
            node: node
        ) || showsDownloadsDeleteMenu
    }

    private var showsDownloadsDeleteMenu: Bool {
        guard plexServer.isDownloadsServer else { return false }
        if case .show = node { return true }
        return false
    }

    func body(content: Content) -> some View {
        Group {
            if offersContextMenu {
                content
                    .contentShape(Rectangle())
                    .contextMenu {
                        if canManage, let ratingKey {
                            mediaMetadataAdminMenuButtons(
                                plexServer: plexServer,
                                ratingKey: ratingKey,
                                showFixMatch: $state.showFixMatch,
                                showEditMetadata: $state.showEditMetadata,
                                showRefreshConfirm: $state.showRefreshConfirm,
                                showDeleteConfirm: $state.showDeleteConfirm,
                                showOptimizeConfirm: $state.showOptimizeConfirm,
                                isWorking: state.isWorking
                            )
                        }
                        extraMenu()
                    }
            } else {
                content
            }
        }
        .modifier(
                MediaMetadataAdminPresentationModifier(
                    plexServer: plexServer,
                    ratingKey: ratingKey ?? "",
                    title: node.listTitle,
                    summary: nodeListSummary(node),
                    year: node.listYear,
                    showTitle: fixMatchShowTitle,
                    seasonTitle: fixMatchSeasonTitle,
                    sectionType: sectionType,
                    isEnabled: canManage && ratingKey != nil,
                    state: $state,
                    onMetadataUpdated: {}
                )
            )
            .task {
                await MediaMetadataAdminAccess.refreshCapabilitiesIfNeeded(
                    plexServer: plexServer,
                    registry: registry
                )
            }
    }
}

// MARK: - Inline section + tvOS menu

private func nodeListSummary(_ node: PlexCatalogNode) -> String? {
    switch node {
    case .movie(let movie): return movie.summary
    case .show(let show): return show.summary
    case .episode(let episode): return episode.summary
    default: return nil
    }
}

struct MediaMetadataAdminSection: View {
    let plexServer: PlexServer
    let ratingKey: String
    let title: String
    let summary: String?
    let year: Int?
    var showTitle: String? = nil
    var seasonTitle: String? = nil
    var sectionType: PlexSectionType? = nil
    @Binding var state: MediaMetadataAdminState
    var onMetadataUpdated: () async -> Void = {}
    var onItemDeleted: () async -> Void = {}

    @EnvironmentObject private var registry: PlexServerRegistry

    private var canManage: Bool {
        MediaMetadataAdminAccess.canManage(plexServer: plexServer, registry: registry)
    }

    private var showsAdminSection: Bool {
        MediaMetadataAdminAccess.shouldOfferContextMenu(
            plexServer: plexServer,
            registry: registry
        )
    }

    var body: some View {
        if showsAdminSection {
            VStack(alignment: .leading, spacing: 10) {
                Text("Metadata")
                    .font(.headline)
                mediaMetadataAdminActionsMenu(
                    plexServer: plexServer,
                    ratingKey: ratingKey,
                    showFixMatch: $state.showFixMatch,
                    showEditMetadata: $state.showEditMetadata,
                    showRefreshConfirm: $state.showRefreshConfirm,
                    showDeleteConfirm: $state.showDeleteConfirm,
                    showOptimizeConfirm: $state.showOptimizeConfirm,
                    isWorking: state.isWorking,
                    isEnabled: canManage
                )
                .buttonStyle(.pressableBordered)
                if !canManage {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking server permissions…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if state.isWorking {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Updating metadata…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let statusMessage = state.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
#if os(iOS) || os(macOS)
                Text("Requires server admin permissions. Long-press artwork for quick actions.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
#endif
#if os(tvOS)
                Text("Requires server admin permissions. Long-press poster for quick actions.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
#endif
            }
            .mediaMetadataAdmin(
                plexServer: plexServer,
                ratingKey: ratingKey,
                title: title,
                summary: summary,
                year: year,
                state: $state,
                showTitle: showTitle,
                seasonTitle: seasonTitle,
                sectionType: sectionType,
                includesPresentation: true,
                includesContextMenu: false,
                onMetadataUpdated: onMetadataUpdated,
                onItemDeleted: onItemDeleted
            )
        }
    }
}

// MARK: - Catalog node

extension PlexCatalogNode {
    var metadataAdminRatingKey: String? {
        switch self {
        case .movie(let movie): return movie.ratingKey
        case .show(let show): return show.ratingKey
        case .episode(let episode): return episode.ratingKey
        case .season, .musicTrack, .photo: return nil
        }
    }

    var supportsMetadataAdmin: Bool {
        metadataAdminRatingKey != nil
    }
}

// MARK: - Match search

extension PlexMetadataMatchCandidate {
    func matchesSearch(trimmedQuery: String) -> Bool {
        let q = trimmedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let needle = q.lowercased()
        if title.lowercased().contains(needle) { return true }
        if let summary, summary.lowercased().contains(needle) { return true }
        if let year, String(year).contains(needle) { return true }
        return false
    }
}
