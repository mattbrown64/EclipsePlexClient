//
//  EditMetadataSheet.swift
//  EclipsePlexClient
//

import SwiftUI

/// Edit Plex metadata fields for a single library item.
struct EditMetadataSheet: View {
    @Environment(\.dismiss) private var dismiss

    let plexServer: PlexServer
    let ratingKey: String
    let initialTitle: String
    let initialSummary: String?
    let initialYear: Int?
    var onSaved: () async -> Void = {}

    @State private var title: String
    @State private var summary: String
    @State private var yearText: String
    @State private var lockTitle = false
    @State private var lockSummary = false
    @State private var lockYear = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        plexServer: PlexServer,
        ratingKey: String,
        initialTitle: String,
        initialSummary: String?,
        initialYear: Int?,
        onSaved: @escaping () async -> Void = {}
    ) {
        self.plexServer = plexServer
        self.ratingKey = ratingKey
        self.initialTitle = initialTitle
        self.initialSummary = initialSummary
        self.initialYear = initialYear
        self.onSaved = onSaved
        _title = State(initialValue: initialTitle)
        _summary = State(initialValue: initialSummary ?? "")
        _yearText = State(initialValue: initialYear.map(String.init) ?? "")
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
                Section("Title") {
                    TextField("Title", text: $title)
                    Toggle("Lock title", isOn: $lockTitle)
                }
                Section("Summary") {
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(4 ... 8)
                    Toggle("Lock summary", isOn: $lockSummary)
                }
                Section("Year") {
                    TextField("Year", text: $yearText)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                    Toggle("Lock year", isOn: $lockYear)
                }
            }
            .navigationTitle("Edit metadata")
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
        .frame(minWidth: 420, minHeight: 400)
#endif
    }

    @MainActor
    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let year = Int(yearText.trimmingCharacters(in: .whitespacesAndNewlines))
        let request = PlexMetadataEditRequest(
            title: title,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : summary,
            year: year,
            lockTitle: lockTitle,
            lockSummary: lockSummary,
            lockYear: lockYear
        )
        do {
            let client = try PlexMediaServerClient(server: plexServer)
            try await client.updateItemMetadata(ratingKey: ratingKey, edit: request)
            PlexAdminActionLog.record(
                serverName: plexServer.name,
                action: "edit metadata",
                success: true,
                detail: title
            )
            AppToastCenter.show("Saved metadata for \(title)")
            dismiss()
            await onSaved()
        } catch {
            let message = PlexAPIError.from(error)
            errorMessage = message
            PlexAdminActionLog.record(
                serverName: plexServer.name,
                action: "edit metadata",
                success: false,
                detail: message
            )
        }
    }
}
