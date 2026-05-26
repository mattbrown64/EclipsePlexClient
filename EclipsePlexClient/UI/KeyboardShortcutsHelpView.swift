//
//  KeyboardShortcutsHelpView.swift
//  EclipsePlexClient
//

import SwiftUI

/// In-app reference for keyboard and hardware-keyboard navigation.
struct KeyboardShortcutsHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                ForEach(KeyboardShortcutCatalog.sections) { section in
                    sectionCard(section)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Keyboard shortcuts")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Keyboard & navigation", systemImage: "keyboard")
                .font(.headline)
            Text("These shortcuts work on Mac and on iPhone or iPad when a hardware keyboard is connected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func sectionCard(_ section: KeyboardShortcutSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.headline)
            ForEach(section.entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(entry.action)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(entry.keys)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                .font(.subheadline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        KeyboardShortcutsHelpView()
    }
}
