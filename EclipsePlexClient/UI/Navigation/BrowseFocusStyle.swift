//
//  BrowseFocusStyle.swift
//  EclipsePlexClient
//

import SwiftUI

/// Visual treatment for keyboard- and remote-driven browse focus.
enum BrowseFocusChrome: Sendable {
    /// Sidebar server / library rows.
    case sidebarRow
    /// Poster grid tile (movie/show artwork).
    case catalogPoster
    /// List row with leading artwork (`CatalogRowView`).
    case catalogListRow
}

private enum BrowseFocusMetrics {
    static let posterCornerRadius: CGFloat = 12
    static let posterPadding: CGFloat = 10
    static let posterBorderWidth: CGFloat = 3
    static let posterFillOpacity: CGFloat = 0.28
    static let animation: Animation = .easeOut(duration: 0.18)
}

extension View {
    /// Highlights the view when it holds browse focus (keyboard / future remote).
    func browseFocusHighlight(active: Bool, pressed: Bool = false, chrome: BrowseFocusChrome) -> some View {
        modifier(BrowseFocusHighlightModifier(active: active, pressed: pressed, chrome: chrome))
    }

    /// Backward-compatible alias; prefer `browseFocusHighlight(active:chrome:)`.
    func keyboardFocusRing(active: Bool) -> some View {
        browseFocusHighlight(active: active, chrome: .catalogPoster)
    }
}

private struct BrowseFocusHighlightModifier: ViewModifier {
    let active: Bool
    let pressed: Bool
    let chrome: BrowseFocusChrome

    @State private var isHovered = false

    private var isEmphasized: Bool {
        active || isHovered || pressed
    }

    func body(content: Content) -> some View {
        Group {
            switch chrome {
            case .sidebarRow:
                sidebarRowStyle(content: content)
            case .catalogPoster:
                catalogPosterStyle(content: content)
            case .catalogListRow:
                catalogListRowStyle(content: content)
            }
        }
        .animation(BrowseFocusMetrics.animation, value: isEmphasized)
        .animation(BrowseFocusMetrics.animation, value: pressed)
        .accessibilityAddTraits(isEmphasized ? [.isSelected] : [])
#if os(macOS)
        .onHover { isHovered = $0 }
#endif
    }

    @ViewBuilder
    private func sidebarRowStyle(content: Content) -> some View {
        let fillOpacity: CGFloat = pressed ? 0.28 : (active || isHovered ? 0.18 : 0)
        content
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(fillOpacity))
            }
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: isEmphasized ? 4 : 0)
                    .padding(.leading, 2)
            }
    }

    @ViewBuilder
    private func catalogPosterStyle(content: Content) -> some View {
        // Idle cells (the common case in a long catalog) used to pay for a
        // zero-radius shadow + a zero-opacity background fill + zero-opacity
        // stroke. Each still allocates a Core Animation layer for the effect.
        // Render those decorations only when the cell is actually emphasized.
        let base = content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BrowseFocusMetrics.posterPadding)

        if isEmphasized || pressed {
            let fillOpacity: CGFloat = pressed ? 0.42 : BrowseFocusMetrics.posterFillOpacity
            base
                .background {
                    RoundedRectangle(cornerRadius: BrowseFocusMetrics.posterCornerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(fillOpacity))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: BrowseFocusMetrics.posterCornerRadius, style: .continuous)
                        .strokeBorder(
                            Color.accentColor.opacity(pressed ? 1 : 1),
                            lineWidth: BrowseFocusMetrics.posterBorderWidth
                        )
                }
                .shadow(
                    color: Color.accentColor.opacity(0.4),
                    radius: 12,
                    y: 4
                )
                .zIndex(1)
        } else {
            base
        }
    }

    @ViewBuilder
    private func catalogListRowStyle(content: Content) -> some View {
        let base = content
            .padding(.vertical, 4)
            .padding(.horizontal, 6)

        if isEmphasized || pressed {
            let fillOpacity: CGFloat = pressed ? 0.22 : 0.14
            let borderOpacity: CGFloat = pressed ? 0.95 : 0.85
            base
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(fillOpacity))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            Color.accentColor.opacity(borderOpacity),
                            lineWidth: pressed ? 2.5 : 2
                        )
                }
        } else {
            base
        }
    }
}
