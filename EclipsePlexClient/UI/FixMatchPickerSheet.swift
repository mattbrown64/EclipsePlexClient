//
//  FixMatchPickerSheet.swift
//  EclipsePlexClient
//

import SwiftUI

/// Lists Plex metadata match candidates and applies the selected match.
struct FixMatchPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let plexServer: PlexServer
    let ratingKey: String
    let title: String
    let year: Int?
    var showTitle: String?
    var seasonTitle: String?
    var sectionType: PlexSectionType?
    var onMatched: () async -> Void = {}

    @State private var candidates: [PlexMetadataMatchCandidate] = []
    @State private var searchTitle: String
    @State private var searchYearText: String
    @State private var searchShowTitle: String
    @State private var searchSeasonTitle: String
    @State private var limitToYear: Bool
    @State private var filterText = ""
    @State private var isLoading = false
    @State private var isApplying = false
    @State private var errorMessage: String?
    @State private var showSearchOptions = true

    init(
        plexServer: PlexServer,
        ratingKey: String,
        title: String,
        year: Int?,
        showTitle: String? = nil,
        seasonTitle: String? = nil,
        sectionType: PlexSectionType? = nil,
        onMatched: @escaping () async -> Void = {}
    ) {
        self.plexServer = plexServer
        self.ratingKey = ratingKey
        self.title = title
        self.year = year
        self.showTitle = showTitle
        self.seasonTitle = seasonTitle
        self.sectionType = sectionType
        self.onMatched = onMatched
        _searchTitle = State(initialValue: title)
        _searchYearText = State(initialValue: year.map(String.init) ?? "")
        _searchShowTitle = State(initialValue: showTitle ?? "")
        _searchSeasonTitle = State(initialValue: seasonTitle ?? "")
        _limitToYear = State(initialValue: year != nil)
    }

    private var trimmedFilter: String {
        filterText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedCandidates: [PlexMetadataMatchCandidate] {
        candidates.filter { $0.matchesSearch(trimmedQuery: trimmedFilter) }
    }

    private var showsTVFields: Bool {
        if sectionType == .show { return true }
        if showTitle != nil || seasonTitle != nil { return true }
        return !searchShowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !searchSeasonTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var parsedSearchYear: Int? {
        guard limitToYear else { return nil }
        let trimmed = searchYearText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed) else { return nil }
        return value
    }

    private var currentHints: FixMatchSearchHints {
        FixMatchSearchHints(
            title: searchTitle,
            year: parsedSearchYear,
            showTitle: showsTVFields ? searchShowTitle : nil,
            seasonTitle: showsTVFields ? searchSeasonTitle : nil,
            manual: true
        )
    }

    var body: some View {
        NavigationStack {
            List {
                searchOptionsSection
                resultsSection
            }
            .listStyle(.plain)
            .navigationTitle("Fix match")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .searchable(text: $filterText, prompt: Text("Filter results"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isApplying)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Search") {
                        Task { await runSearch() }
                    }
                    .disabled(isLoading || isApplying || currentHints.trimmedTitle == nil)
                }
            }
            .task {
                await runSearch()
            }
        }
#if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
#endif
#if os(tvOS)
        .frame(minWidth: 720, minHeight: 600)
#endif
    }

    private var searchOptionsSection: some View {
        Section {
            DisclosureGroup("Search options", isExpanded: $showSearchOptions) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Title or ID (imdb-tt…, tmdb-…, tvdb-…)", text: $searchTitle)
#if os(iOS)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
#endif
                    }

                    Toggle("Limit to year", isOn: $limitToYear)
                    if limitToYear {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Year")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Year", text: $searchYearText)
#if os(iOS)
                                .keyboardType(.numberPad)
#endif
                        }
                    }

                    if showsTVFields {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TV show")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Series title", text: $searchShowTitle)
#if os(iOS)
                                .textInputAutocapitalization(.words)
#endif
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Season")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("e.g. Season 1", text: $searchSeasonTitle)
#if os(iOS)
                                .textInputAutocapitalization(.words)
#endif
                        }
                    }

                    Text(externalIDHelp)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task { await runSearch() }
                    } label: {
                        Label("Search Plex", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pressableBorderedProminent)
                    .disabled(isLoading || currentHints.trimmedTitle == nil)

                    Button("Reset to file info") {
                        resetSearchFields()
                    }
                    .buttonStyle(.pressableBordered)
                    .font(.caption)
                }
                .padding(.vertical, 4)
            }
        } footer: {
            Text("Change title, year, or use an external ID when automatic matches are wrong.")
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        Section {
            if isLoading, candidates.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Searching Plex…")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if let errorMessage, candidates.isEmpty {
                ContentUnavailableView {
                    Label("Search failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                }
                .listRowBackground(Color.clear)
            } else if displayedCandidates.isEmpty {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "No matches",
                        systemImage: "questionmark.circle",
                        description: Text("Open Search options and try another title, year, or external ID.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ContentUnavailableView.search(text: filterText)
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(displayedCandidates) { candidate in
                    Button {
                        Task { await apply(candidate) }
                    } label: {
                        matchRow(candidate)
                    }
                    .disabled(isApplying)
                }
            }
        } header: {
            if !candidates.isEmpty {
                Text("\(displayedCandidates.count) of \(candidates.count) matches")
            } else {
                Text("Matches")
            }
        }
    }

    private var externalIDHelp: String {
        switch sectionType {
        case .music:
            return "Music: use a MusicBrainz release ID in Title, e.g. mb-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx."
        case .show:
            return "TV: title can be tvdb-74550, tmdb-1855, or imdb-tt0112178. Turn off “Limit to year” for broader results."
        default:
            return "Movies: title can be imdb-tt0111161 or tmdb-550. Turn off “Limit to year” to search any release year."
        }
    }

    @ViewBuilder
    private func matchRow(_ candidate: PlexMetadataMatchCandidate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let thumbPath = candidate.thumbPath {
                CatalogArtworkImage(
                    plexServer: plexServer,
                    thumbPath: thumbPath,
                    style: .list,
                    showsDownloadedBadge: false
                )
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let year = candidate.year {
                    Text(String(year))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let summary = candidate.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            if isApplying {
                ProgressView()
            }
        }
        .padding(.vertical, 4)
    }

    private func resetSearchFields() {
        searchTitle = title
        searchYearText = year.map(String.init) ?? ""
        searchShowTitle = showTitle ?? ""
        searchSeasonTitle = seasonTitle ?? ""
        limitToYear = year != nil
        filterText = ""
    }

    @MainActor
    private func runSearch() async {
        guard currentHints.trimmedTitle != nil else {
            errorMessage = "Enter a title or external ID to search."
            candidates = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let client = try PlexMediaServerClient(server: plexServer)
            candidates = try await client.fetchMetadataMatchCandidates(
                ratingKey: ratingKey,
                hints: currentHints
            )
            if candidates.isEmpty {
                errorMessage = nil
            }
        } catch {
            candidates = []
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func apply(_ candidate: PlexMetadataMatchCandidate) async {
        isApplying = true
        defer { isApplying = false }
        do {
            let client = try PlexMediaServerClient(server: plexServer)
            try await client.applyMetadataMatch(ratingKey: ratingKey, guid: candidate.guid)
            AppToastCenter.show("Matched to \(candidate.title)")
            dismiss()
            await onMatched()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
