# EclipsePlexClient

SwiftUI Plex client for **iOS**, **iPadOS**, **macOS**, and **tvOS**. Browse libraries, play media with VLC, and manage offline downloads.

## Features

- Plex PIN sign-in, server discovery, and manual server add
- VLC playback with direct play, transcode, and optional HLS / Picture in Picture (see [Docs/VLCUI.md](Docs/VLCUI.md))
- Mini player bar while browsing; lock-screen Now Playing on iOS
- Visual themes, keyboard navigation (Mac / iPad), and Siri Remote focus on tvOS
- Offline downloads with background resume (iOS) and scrobble retry
- Server management and metadata tools for admin-capable servers (see [Docs/ServerManagement.md](Docs/ServerManagement.md))

## Requirements

- Xcode 16+ with SDKs for **iOS 26+**, **macOS 14+**, and **tvOS 17+** (aligned in project, Podfile, and CI)
- [CocoaPods](https://cocoapods.org/) for iOS / tvOS VLCKit
- macOS: vendored `Frameworks/VLCKit.xcframework` (see [Docs/VLCUI.md](Docs/VLCUI.md))

## Quick start

```bash
cd /path/to/EclipsePlexClient
pod install
open EclipsePlexClient.xcworkspace
```

Always open the **workspace**, not the `.xcodeproj`, when building for iPhone or Apple TV.

## Keyboard navigation (Mac / iPad with keyboard)

| Key | Action |
|-----|--------|
| ⌘⇧B | Open browse sidebar |
| ⌘F | Search current Plex server |
| ↑ ↓ | Move focus (sidebar, home hubs, or catalog) |
| ← → | Home hubs / catalog grid; from sidebar → enters detail |
| Tab | Toggle sidebar ↔ detail |
| Return | Open selection |
| E | Back |

Full list: [Docs/KeyboardShortcuts.md](Docs/KeyboardShortcuts.md) and **Settings → Keyboard shortcuts** in the app.

## Project layout

| Path | Purpose |
|------|---------|
| `EclipsePlexClient/UI/` | SwiftUI shell, catalog, player chrome |
| `EclipsePlexClient/BackEnd/` | Plex API and catalog models (canonical; on case-insensitive volumes do not add a separate `Backend/` folder) |
| `EclipsePlexClient/Playback/` | VLCUI + platform players |
| `EclipsePlexClient/Offline/` | Download queue and local library |
| `EclipsePlexClientTests/` | Unit tests (focus coordinator, grid layout) |
| `EclipsePlexClientUITests/` | UI smoke tests (browse menu, sidebar) |

## Tests

**Unit tests** (`EclipsePlexClientTests`, Swift Testing): keyboard focus coordinator, sidebar row order, catalog grid layout, Plex markers/XML, offline download catalog/validator, sample search, playback preferences, and more.

**UI tests** (`EclipsePlexClientUITests`): launch smoke, browse sidebar, and playback chrome with `-UITestSeedSampleData` (fixture servers/libraries).

```bash
# Unit tests (macOS)
xcodebuild -workspace EclipsePlexClient.xcworkspace \
  -scheme EclipsePlexClient \
  -destination 'platform=macOS' \
  -only-testing:EclipsePlexClientTests \
  test

# UI tests (iPhone Simulator example)
xcodebuild -workspace EclipsePlexClient.xcworkspace \
  -scheme EclipsePlexClient \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:EclipsePlexClientUITests \
  test
```

CI (`.github/workflows/ci.yml`) runs deployment-target checks, macOS unit tests, iOS unit tests, UI smoke tests, and tvOS build on push/PR to `main`.

## Production readiness

See [Docs/ProductionReadiness.md](Docs/ProductionReadiness.md) and [Docs/ReleaseChecklist.md](Docs/ReleaseChecklist.md). Privacy policy template: [Docs/PrivacyPolicy.md](Docs/PrivacyPolicy.md).

## tvOS

Apple TV shares the iOS browse overlay shell (`NavigationStack` + sidebar sheet). Run `./scripts/fetch-tvvlckit.sh`, then build for **Apple TV Simulator** from the workspace.

Siri Remote focus: `TVBrowseFocus.swift` (`focusSection` on sidebar, home hubs, catalog, detail). See [Docs/KeyboardShortcuts.md](Docs/KeyboardShortcuts.md).

## License

EclipsePlexClient source is [MIT](LICENSE).

Third-party playback libraries:

- VLCKit (LGPL) — [VideoLAN VLCKit](https://github.com/videolan/vlckit)
- VLCUI (MIT) — [LePips/VLCUI](https://github.com/LePips/VLCUI)
