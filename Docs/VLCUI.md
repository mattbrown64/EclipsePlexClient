# VLCUI playback

Cross-platform SwiftUI playback uses [VLCUI](https://github.com/LePips/VLCUI) with platform-specific VLCKit binaries.

| Platform | VLCKit source |
|----------|----------------|
| iOS / iOS Simulator | [MobileVLCKit](https://cocoapods.org/pods/MobileVLCKit) (CocoaPods) |
| macOS | `Frameworks/VLCKit.xcframework` (vendored 3.6.0) |
| visionOS | Not supported by VLCUI yet — use another player if you add a visionOS target |

## Open the workspace

```bash
cd /path/to/EclipsePlexClient
pod install
open EclipsePlexClient.xcworkspace
```

If macOS build fails with a missing `VLCKit.xcframework`, run:

```bash
./Scripts/fetch-vlckit-macos.sh
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

If the debugger stops in `dyld::__abort_with_payload` and the console mentions **different Team IDs** for `VLCKit.framework`, the embed script did not re-sign the framework. Ensure **Signing & Capabilities** uses your Development team (not “Sign to Run Locally” only), then **Clean Build Folder** and run again. The `Embed VLCKit (macOS)` build phase runs `Scripts/embed-vlckit-macos.sh` to re-sign the prebuilt framework with your team.
