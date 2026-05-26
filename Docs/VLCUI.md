# VLCUI playback

Cross-platform SwiftUI playback uses [VLCUI](https://github.com/LePips/VLCUI) with platform-specific VLCKit binaries.

| Platform | VLCKit source |
|----------|----------------|
| iOS / iOS Simulator | [MobileVLCKit](https://cocoapods.org/pods/MobileVLCKit) (CocoaPods) |
| macOS | `Frameworks/VLCKit.xcframework` (vendored 3.6.0) |
| tvOS | `Frameworks/TVVLCKit.xcframework` via `./scripts/fetch-tvvlckit.sh` (CocoaPods cannot mix MobileVLCKit + TVVLCKit in one Podfile) |

## Open the workspace (required)

**iOS requires CocoaPods.** You must use the **workspace** — opening `EclipsePlexClient.xcodeproj` alone will produce `unable to resolve module dependency: MobileVLCKit`.

```bash
cd /path/to/EclipsePlexClient
pod install
open EclipsePlexClient.xcworkspace
# or: ./scripts/open-xcode.sh
```

In Xcode, select an **iPhone Simulator** destination (not “My Mac”) when building iOS.

### “Unable to resolve module dependency: MobileVLCKit”

1. From the repo root, run `pod install` (creates `Pods/MobileVLCKit/`).
2. Quit Xcode completely.
3. Open **`EclipsePlexClient.xcworkspace`** (double-check the window title — not `.xcodeproj`).
4. **Product → Clean Build Folder**, then build for **iPhone Simulator**.

If it still fails:

```bash
pod deintegrate && pod install
open EclipsePlexClient.xcworkspace
```

**Cursor / VS Code:** Swift diagnostics may still show the error on Mac until you build once from the workspace; use `./scripts/open-xcode.sh` or set `sweetpad.workspacePath` to `EclipsePlexClient.xcworkspace` in `.vscode/settings.json`.

If macOS build fails with a missing `VLCKit.xcframework`, run:

```bash
./scripts/fetch-vlckit-macos.sh
```

For **Apple TV** builds, install TVVLCKit then add `FRAMEWORK_SEARCH_PATHS` for `appletvos*` to `Frameworks/TVVLCKit.xcframework` in Xcode if needed:

```bash
./scripts/fetch-tvvlckit.sh
```

## Usage

```swift
import VLCUI

VLCVideoPlayer(configuration: .init(url: streamURL))
```

See the [VLCUI README](https://github.com/LePips/VLCUI) for proxies, state callbacks, and configuration options.

## Dependencies

- **VLCUI sources:** vendored under `EclipsePlexClient/Playback/VLCUI/` ([upstream](https://github.com/LePips/VLCUI) 0.8.1) — compiled in-app so CocoaPods can supply `MobileVLCKit`
- **CocoaPods:** `MobileVLCKit ~> 3.6.0` (iOS only)
- **Vendored:** VLCKit 3.6.0 XCFramework for macOS ([VideoLAN download](https://download.videolan.org/pub/cocoapods/prod/))

VLCKit is LGPL — see [VideoLAN VLCKit](https://github.com/videolan/vlckit).

### macOS: dyld crash on launch

If the debugger stops in `dyld::__abort_with_payload` and the console mentions **different Team IDs** for `VLCKit.framework`, the embed script did not re-sign the framework. Ensure **Signing & Capabilities** uses your Development team (not “Sign to Run Locally” only), then **Clean Build Folder** and run again. The `Embed VLCKit (macOS)` build phase runs `scripts/embed-vlckit-macos.sh` to re-sign the prebuilt framework with your team.
