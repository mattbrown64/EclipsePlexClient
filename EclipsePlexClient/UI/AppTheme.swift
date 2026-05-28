//
//  AppTheme.swift
//  EclipsePlexClient
//

import SwiftUI

/// Full visual theme: accent tint plus browse/player gradients.
struct AppThemePalette: Equatable {
    let accent: Color
    let shellGradient: [Color]
    let playerGradient: [Color]

    var shellGradientPoints: (UnitPoint, UnitPoint) {
        (.topLeading, .bottomTrailing)
    }

    var playerGradientPoints: (UnitPoint, UnitPoint) {
        (.topLeading, .bottomTrailing)
    }
}

enum AppVisualTheme: String, CaseIterable, Identifiable {
    case system
    case eclipse
    case midnightOcean
    case sunsetBoulevard
    case neonArcade
    case forestRetreat
    case lavenderSky
    case cherryPop
    case goldenHour
    case arcticGlow
    case retroWave
    case matrixCode

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .eclipse: "Eclipse"
        case .midnightOcean: "Midnight Ocean"
        case .sunsetBoulevard: "Sunset Boulevard"
        case .neonArcade: "Neon Arcade"
        case .forestRetreat: "Forest Retreat"
        case .lavenderSky: "Lavender Sky"
        case .cherryPop: "Cherry Pop"
        case .goldenHour: "Golden Hour"
        case .arcticGlow: "Arctic Glow"
        case .retroWave: "Retro Wave"
        case .matrixCode: "Matrix Code"
        }
    }

    var palette: AppThemePalette? {
        switch self {
        case .system:
            return nil
        case .eclipse:
            return AppThemePalette(
                accent: Color(red: 0.94, green: 0.34, blue: 0.36),
                shellGradient: [
                    Color(red: 0.14, green: 0.06, blue: 0.08),
                    Color(red: 0.20, green: 0.08, blue: 0.10),
                    Color(red: 0.08, green: 0.05, blue: 0.06)
                ],
                playerGradient: [
                    Color(red: 0.12, green: 0.06, blue: 0.08),
                    Color(red: 0.18, green: 0.08, blue: 0.10),
                    Color(red: 0.06, green: 0.04, blue: 0.05)
                ]
            )
        case .midnightOcean:
            return AppThemePalette(
                accent: Color(red: 0.20, green: 0.72, blue: 0.95),
                shellGradient: [
                    Color(red: 0.03, green: 0.10, blue: 0.22),
                    Color(red: 0.05, green: 0.18, blue: 0.30),
                    Color(red: 0.02, green: 0.08, blue: 0.16)
                ],
                playerGradient: [
                    Color(red: 0.02, green: 0.12, blue: 0.24),
                    Color(red: 0.04, green: 0.22, blue: 0.34),
                    Color(red: 0.01, green: 0.08, blue: 0.18)
                ]
            )
        case .sunsetBoulevard:
            return AppThemePalette(
                accent: Color(red: 1.0, green: 0.45, blue: 0.22),
                shellGradient: [
                    Color(red: 0.22, green: 0.08, blue: 0.12),
                    Color(red: 0.30, green: 0.10, blue: 0.18),
                    Color(red: 0.14, green: 0.06, blue: 0.10)
                ],
                playerGradient: [
                    Color(red: 0.28, green: 0.10, blue: 0.14),
                    Color(red: 0.42, green: 0.14, blue: 0.20),
                    Color(red: 0.18, green: 0.08, blue: 0.12)
                ]
            )
        case .neonArcade:
            return AppThemePalette(
                accent: Color(red: 0.0, green: 0.92, blue: 0.98),
                shellGradient: [
                    Color(red: 0.08, green: 0.04, blue: 0.18),
                    Color(red: 0.12, green: 0.06, blue: 0.26),
                    Color(red: 0.05, green: 0.03, blue: 0.14)
                ],
                playerGradient: [
                    Color(red: 0.10, green: 0.04, blue: 0.22),
                    Color(red: 0.16, green: 0.08, blue: 0.30),
                    Color(red: 0.06, green: 0.03, blue: 0.16)
                ]
            )
        case .forestRetreat:
            return AppThemePalette(
                accent: Color(red: 0.28, green: 0.78, blue: 0.42),
                shellGradient: [
                    Color(red: 0.06, green: 0.12, blue: 0.08),
                    Color(red: 0.08, green: 0.18, blue: 0.12),
                    Color(red: 0.04, green: 0.10, blue: 0.07)
                ],
                playerGradient: [
                    Color(red: 0.05, green: 0.14, blue: 0.09),
                    Color(red: 0.10, green: 0.22, blue: 0.14),
                    Color(red: 0.03, green: 0.10, blue: 0.07)
                ]
            )
        case .lavenderSky:
            return AppThemePalette(
                accent: Color(red: 0.72, green: 0.55, blue: 0.98),
                shellGradient: [
                    Color(red: 0.14, green: 0.10, blue: 0.22),
                    Color(red: 0.20, green: 0.14, blue: 0.30),
                    Color(red: 0.10, green: 0.08, blue: 0.18)
                ],
                playerGradient: [
                    Color(red: 0.16, green: 0.12, blue: 0.26),
                    Color(red: 0.24, green: 0.16, blue: 0.34),
                    Color(red: 0.12, green: 0.10, blue: 0.20)
                ]
            )
        case .cherryPop:
            return AppThemePalette(
                accent: Color(red: 1.0, green: 0.28, blue: 0.52),
                shellGradient: [
                    Color(red: 0.20, green: 0.06, blue: 0.14),
                    Color(red: 0.28, green: 0.08, blue: 0.18),
                    Color(red: 0.14, green: 0.05, blue: 0.10)
                ],
                playerGradient: [
                    Color(red: 0.24, green: 0.08, blue: 0.16),
                    Color(red: 0.34, green: 0.10, blue: 0.22),
                    Color(red: 0.16, green: 0.06, blue: 0.12)
                ]
            )
        case .goldenHour:
            return AppThemePalette(
                accent: Color(red: 0.98, green: 0.72, blue: 0.18),
                shellGradient: [
                    Color(red: 0.18, green: 0.10, blue: 0.06),
                    Color(red: 0.26, green: 0.14, blue: 0.08),
                    Color(red: 0.12, green: 0.08, blue: 0.05)
                ],
                playerGradient: [
                    Color(red: 0.22, green: 0.12, blue: 0.06),
                    Color(red: 0.32, green: 0.18, blue: 0.08),
                    Color(red: 0.14, green: 0.08, blue: 0.04)
                ]
            )
        case .arcticGlow:
            return AppThemePalette(
                accent: Color(red: 0.42, green: 0.78, blue: 0.98),
                shellGradient: [
                    Color(red: 0.88, green: 0.94, blue: 0.98),
                    Color(red: 0.78, green: 0.90, blue: 0.98),
                    Color(red: 0.92, green: 0.96, blue: 1.0)
                ],
                playerGradient: [
                    Color(red: 0.72, green: 0.86, blue: 0.96),
                    Color(red: 0.58, green: 0.78, blue: 0.94),
                    Color(red: 0.82, green: 0.90, blue: 0.98)
                ]
            )
        case .retroWave:
            return AppThemePalette(
                accent: Color(red: 0.98, green: 0.22, blue: 0.72),
                shellGradient: [
                    Color(red: 0.12, green: 0.04, blue: 0.20),
                    Color(red: 0.18, green: 0.06, blue: 0.28),
                    Color(red: 0.08, green: 0.03, blue: 0.16)
                ],
                playerGradient: [
                    Color(red: 0.14, green: 0.05, blue: 0.24),
                    Color(red: 0.22, green: 0.08, blue: 0.32),
                    Color(red: 0.10, green: 0.04, blue: 0.18)
                ]
            )
        case .matrixCode:
            return AppThemePalette(
                accent: Color(red: 0.32, green: 0.95, blue: 0.38),
                shellGradient: [
                    Color(red: 0.02, green: 0.06, blue: 0.03),
                    Color(red: 0.04, green: 0.10, blue: 0.05),
                    Color(red: 0.01, green: 0.04, blue: 0.02)
                ],
                playerGradient: [
                    Color(red: 0.02, green: 0.08, blue: 0.04),
                    Color(red: 0.05, green: 0.14, blue: 0.06),
                    Color(red: 0.01, green: 0.05, blue: 0.03)
                ]
            )
        }
    }

    /// Maps legacy accent-only presets to the closest full theme.
    static func migrated(fromLegacyAccent rawValue: String) -> AppVisualTheme {
        switch rawValue {
        case "system": return .system
        case "blue": return .midnightOcean
        case "purple": return .lavenderSky
        case "emerald": return .forestRetreat
        case "orange": return .goldenHour
        case "pink": return .cherryPop
        case "cyan": return .neonArcade
        case "lime": return .matrixCode
        case "ruby": return .cherryPop
        case "gold": return .goldenHour
        case "indigo": return .eclipse
        default: return .eclipse
        }
    }
}

enum AppThemeStorage {
    private static let visualThemeKey = "appVisualTheme"
    private static let legacyAccentKey = "appAccentTheme"

    static func loadVisualTheme() -> AppVisualTheme {
        if let stored = UserDefaults.standard.string(forKey: visualThemeKey),
           let theme = AppVisualTheme(rawValue: stored) {
            return theme
        }
        if let legacy = UserDefaults.standard.string(forKey: legacyAccentKey) {
            let migrated = AppVisualTheme.migrated(fromLegacyAccent: legacy)
            UserDefaults.standard.set(migrated.rawValue, forKey: visualThemeKey)
            return migrated
        }
        return .eclipse
    }

    static func saveVisualTheme(_ theme: AppVisualTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: visualThemeKey)
    }
}

private struct AppThemePaletteKey: EnvironmentKey {
    static let defaultValue: AppThemePalette? = nil
}

private struct ThemeAccentKey: EnvironmentKey {
    static let defaultValue = Color.accentColor
}

extension EnvironmentValues {
    var appThemePalette: AppThemePalette? {
        get { self[AppThemePaletteKey.self] }
        set { self[AppThemePaletteKey.self] = newValue }
    }

    /// Resolved theme accent — use anywhere system accent color would appear.
    var themeAccent: Color {
        get { self[ThemeAccentKey.self] }
        set { self[ThemeAccentKey.self] = newValue }
    }
}

struct AppThemedShellBackground: ViewModifier {
    let palette: AppThemePalette?

    func body(content: Content) -> some View {
        content.background {
            if let palette {
                let (start, end) = palette.shellGradientPoints
                LinearGradient(colors: palette.shellGradient, startPoint: start, endPoint: end)
                    .opacity(0.55)
                    .ignoresSafeArea()
            }
        }
    }
}

extension View {
    func appThemedShellBackground(_ palette: AppThemePalette?) -> some View {
        modifier(AppThemedShellBackground(palette: palette))
    }
}

struct AppThemeSwatch: View {
    let theme: AppVisualTheme

    var body: some View {
        if let palette = theme.palette {
            let (start, end) = palette.shellGradientPoints
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [palette.accent] + palette.shellGradient.prefix(2),
                        startPoint: start,
                        endPoint: end
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                }
                .frame(width: 28, height: 18)
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 28, height: 18)
        }
    }
}
