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
    func browseFocusHighlight(active: Bool, chrome: BrowseFocusChrome) -> some View {
        modifier(BrowseFocusHighlightModifier(active: active, chrome: chrome))
    }

    /// Backward-compatible alias; prefer `browseFocusHighlight(active:chrome:)`.
    func keyboardFocusRing(active: Bool) -> some View {
        browseFocusHighlight(active: active, chrome: .catalogPoster)
    }
}

private struct BrowseFocusHighlightModifier: ViewModifier {
    let active: Bool
    let chrome: BrowseFocusChrome

    @State private var isHovered = false

    private var isEmphasized: Bool {
        active || isHovered
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
        .accessibilityAddTraits(isEmphasized ? [.isSelected] : [])
#if os(macOS)
        .onHover { isHovered = $0 }
#endif
    }

    @ViewBuilder
    private func sidebarRowStyle(content: Content) -> some View {
        content
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(isEmphasized ? 0.18 : 0))
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
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BrowseFocusMetrics.posterPadding)
            .background {
                RoundedRectangle(cornerRadius: BrowseFocusMetrics.posterCornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(isEmphasized ? BrowseFocusMetrics.posterFillOpacity : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: BrowseFocusMetrics.posterCornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.accentColor.opacity(isEmphasized ? 1 : 0),
                        lineWidth: BrowseFocusMetrics.posterBorderWidth
                    )
            }
            .shadow(
                color: Color.accentColor.opacity(isEmphasized ? 0.4 : 0),
                radius: isEmphasized ? 12 : 0,
                y: isEmphasized ? 4 : 0
            )
            .zIndex(isEmphasized ? 1 : 0)
    }

    @ViewBuilder
    private func catalogListRowStyle(content: Content) -> some View {
        content
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(isEmphasized ? 0.14 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Color.accentColor.opacity(isEmphasized ? 0.85 : 0),
                        lineWidth: 2
                    )
            }
    }
}
