//
//  EclipsePlexButtonStyle.swift
//  EclipsePlexClient
//

import SwiftUI

private enum PressFeedbackMetrics {
    static let animation: Animation = .easeOut(duration: 0.12)
    static let pressedScale: CGFloat = 0.96
    static let plainPressedScale: CGFloat = 0.97
    static let pressedOpacity: CGFloat = 0.72
}

/// Plain buttons (sidebar rows, tiles) with visible press feedback.
struct PressablePlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? PressFeedbackMetrics.pressedOpacity : 1)
            .scaleEffect(configuration.isPressed ? PressFeedbackMetrics.plainPressedScale : 1)
            .animation(PressFeedbackMetrics.animation, value: configuration.isPressed)
    }
}

/// Plain browse controls that also show keyboard/remote focus chrome.
struct BrowsePressableButtonStyle: ButtonStyle {
    var isFocused: Bool
    var chrome: BrowseFocusChrome

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? PressFeedbackMetrics.plainPressedScale : 1)
            .browseFocusHighlight(
                active: isFocused,
                pressed: configuration.isPressed,
                chrome: chrome
            )
            .animation(PressFeedbackMetrics.animation, value: configuration.isPressed)
    }
}

/// Bordered action buttons with a clear pressed state.
struct PressableBorderedButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(.primary)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.07))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(configuration.isPressed ? 0.4 : 0.2),
                        lineWidth: configuration.isPressed ? 1.5 : 1
                    )
            }
            .scaleEffect(configuration.isPressed ? PressFeedbackMetrics.pressedScale : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(PressFeedbackMetrics.animation, value: configuration.isPressed)
    }
}

/// Prominent call-to-action buttons with a clear pressed state.
struct PressableBorderedProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.themeAccent) private var themeAccent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(Color.white)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(themeAccent.opacity(configuration.isPressed ? 0.72 : 1))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(configuration.isPressed ? 0.35 : 0.15), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? PressFeedbackMetrics.pressedScale : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(PressFeedbackMetrics.animation, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressablePlainButtonStyle {
    static var pressablePlain: PressablePlainButtonStyle { PressablePlainButtonStyle() }
}

extension ButtonStyle where Self == PressableBorderedButtonStyle {
    static var pressableBordered: PressableBorderedButtonStyle { PressableBorderedButtonStyle() }
}

extension ButtonStyle where Self == PressableBorderedProminentButtonStyle {
    static var pressableBorderedProminent: PressableBorderedProminentButtonStyle {
        PressableBorderedProminentButtonStyle()
    }
}

extension ButtonStyle where Self == BrowsePressableButtonStyle {
    static func browsePressable(focused: Bool, chrome: BrowseFocusChrome) -> BrowsePressableButtonStyle {
        BrowsePressableButtonStyle(isFocused: focused, chrome: chrome)
    }
}

enum PlatformControlSize {
    case small, regular, large
}

extension View {
    /// `controlSize` is unavailable on tvOS; no-op there.
    @ViewBuilder
    func platformControlSize(_ size: PlatformControlSize) -> some View {
#if os(tvOS)
        self
#else
        switch size {
        case .small: controlSize(.small)
        case .regular: controlSize(.regular)
        case .large: controlSize(.large)
        }
#endif
    }
}
