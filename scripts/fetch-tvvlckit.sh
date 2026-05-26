#!/usr/bin/env bash
# Fetches TVVLCKit.xcframework for Apple TV builds (CocoaPods cannot mix MobileVLCKit + TVVLCKit in one iOS-platform Podfile).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Frameworks/TVVLCKit.xcframework"
WORK="$ROOT/.build/tvvlckit-pod"
PODFILE="$WORK/Podfile"

if [[ -d "$DEST" ]]; then
  echo "TVVLCKit.xcframework already exists at $DEST"
  exit 0
fi

mkdir -p "$WORK"
cat > "$PODFILE" <<'RUBY'
install! 'cocoapods', :integrate_targets => false
platform :tvos, '17.0'
target 'TVVLCKitFetcher' do
  use_frameworks!
  pod 'TVVLCKit', '~> 3.6.0'
end
RUBY

echo "Installing TVVLCKit via auxiliary CocoaPods project..."
(cd "$WORK" && pod install 2>&1 | tail -5)

XC="$(find "$WORK/Pods/TVVLCKit" -name 'TVVLCKit.xcframework' -maxdepth 4 | head -1)"
if [[ -z "$XC" ]]; then
  echo "Could not locate TVVLCKit.xcframework under $WORK/Pods" >&2
  exit 1
fi

mkdir -p "$ROOT/Frameworks"
cp -R "$XC" "$DEST"
echo "Installed $DEST"
