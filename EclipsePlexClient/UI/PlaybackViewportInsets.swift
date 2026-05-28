//
//  PlaybackViewportInsets.swift
//  EclipsePlexClient
//

import SwiftUI

#if os(iOS)
import UIKit

/// Window safe-area insets for playback chrome. SwiftUI overlays during forced
/// landscape rotation often report zero insets unless read from UIKit directly.
enum PlaybackViewportInsets {
    @MainActor
    static var edgeInsets: EdgeInsets {
        guard let window = keyWindow else { return EdgeInsets() }
        let ui = window.safeAreaInsets
        return EdgeInsets(
            top: ui.top,
            leading: ui.left,
            bottom: ui.bottom,
            trailing: ui.right
        )
    }

    @MainActor
    static func chromeInsets(in geometry: GeometryProxy) -> EdgeInsets {
        let geo = geometry.safeAreaInsets
        let ui = edgeInsets
        var merged = EdgeInsets(
            top: max(geo.top, ui.top),
            leading: max(geo.leading, ui.leading),
            bottom: max(geo.bottom, ui.bottom),
            trailing: max(geo.trailing, ui.trailing)
        )

        let isLandscape = geometry.size.width > geometry.size.height
        if isLandscape {
            // Landscape often reports 0 on the short edges; keep controls off rounded corners.
            let minimumShortEdge: CGFloat = 24
            merged.top = max(merged.top, minimumShortEdge)
            merged.bottom = max(merged.bottom, minimumShortEdge)
        } else {
            // Portrait home indicator.
            merged.bottom = max(merged.bottom, 34)
        }

        return merged
    }

    @MainActor
    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}
#endif
