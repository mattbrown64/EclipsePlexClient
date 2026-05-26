//
//  CatalogBrowsePreferences.swift
//  EclipsePlexClient
//

import Foundation

/// Top-level tabs when browsing a library at its root (official Plex-style).
nonisolated enum LibraryRootTab: String, Sendable, CaseIterable, Identifiable {
    case recommended
    case browse
    case collections

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recommended: "Recommended"
        case .browse: "Browse"
        case .collections: "Collections"
        }
    }
}

nonisolated enum LibraryBrowsePreferences {
    static func rootTabStorageKey(serverId: UUID, libraryId: String) -> String {
        "libraryRootTab.v1.\(serverId.uuidString).\(libraryId)"
    }

    static func loadRootTab(serverId: UUID, libraryId: String) -> LibraryRootTab? {
        guard let raw = UserDefaults.standard.string(forKey: rootTabStorageKey(serverId: serverId, libraryId: libraryId)) else {
            return nil
        }
        return LibraryRootTab(rawValue: raw)
    }

    static func saveRootTab(_ tab: LibraryRootTab, serverId: UUID, libraryId: String) {
        UserDefaults.standard.set(tab.rawValue, forKey: rootTabStorageKey(serverId: serverId, libraryId: libraryId))
    }

    static func showsCollectionsTab(sectionType: PlexSectionType) -> Bool {
        sectionType == .movie || sectionType == .show
    }

    static func showsRecommendedTab(sectionType: PlexSectionType, usesLiveAPI: Bool) -> Bool {
        usesLiveAPI && (sectionType == .movie || sectionType == .show || sectionType == .music)
    }
}

nonisolated enum CatalogViewMode: String, Sendable, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .list: "List"
        case .grid: "Grid"
        }
    }

    var icon: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        }
    }
}

nonisolated enum CatalogBrowsePreferences {
    /// Default view mode on first visit: grid at library root, list for show/season episode lists.
    static func defaultViewMode(parent: PlexCatalogParent) -> CatalogViewMode {
        switch parent {
        case .root, .collection, .playlist:
            return .grid
        case .show, .season:
            return .list
        }
    }

    static func viewModeStorageKey(serverId: UUID, libraryId: String, parent: PlexCatalogParent) -> String {
        let parentKey = parentStorageKey(parent)
        return "catalogViewMode.v1.\(serverId.uuidString).\(libraryId).\(parentKey)"
    }

    static func loadViewMode(
        serverId: UUID,
        libraryId: String,
        parent: PlexCatalogParent
    ) -> CatalogViewMode? {
        let key = viewModeStorageKey(serverId: serverId, libraryId: libraryId, parent: parent)
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return CatalogViewMode(rawValue: raw)
    }

    static func saveViewMode(
        _ mode: CatalogViewMode,
        serverId: UUID,
        libraryId: String,
        parent: PlexCatalogParent
    ) {
        let key = viewModeStorageKey(serverId: serverId, libraryId: libraryId, parent: parent)
        UserDefaults.standard.set(mode.rawValue, forKey: key)
    }

    private static func parentStorageKey(_ parent: PlexCatalogParent) -> String {
        switch parent {
        case .root: return "root"
        case .show(let k): return "show:\(k)"
        case .season(let k): return "season:\(k)"
        case .collection(let k): return "collection:\(k)"
        case .playlist(let k): return "playlist:\(k)"
        }
    }
}

nonisolated enum PlexSectionSortQuery {
    /// Maps Plex library section `sort` to `sort=` query value; nil keeps server response order.
    static func queryValue(plexDefaultSortKey: String?) -> String? {
        guard let raw = plexDefaultSortKey?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.contains(":") { return raw }
        return "\(raw):asc"
    }

    static func queryItems(plexDefaultSortKey: String?) -> [URLQueryItem] {
        guard let value = queryValue(plexDefaultSortKey: plexDefaultSortKey) else { return [] }
        return [URLQueryItem(name: "sort", value: value)]
    }
}
