#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Frameworks/VLCKit.xcframework"
ARCHIVE="/tmp/VLCKit-3.6.0.tar.xz"
URL="https://download.videolan.org/pub/cocoapods/prod/VLCKit-3.6.0-c73b779f-dd8bfdba.tar.xz"

if [[ -d "$DEST" ]]; then
  echo "VLCKit.xcframework already exists at $DEST"
  exit 0
fi

echo "Downloading VLCKit 3.6.0 for macOS..."
curl -L -o "$ARCHIVE" "$URL"
mkdir -p "$ROOT/Frameworks"
tar -xf "$ARCHIVE" -C /tmp "VLCKit - binary package/VLCKit.xcframework"
mv "/tmp/VLCKit - binary package/VLCKit.xcframework" "$DEST"
rm -rf "/tmp/VLCKit - binary package"
echo "Installed $DEST"
