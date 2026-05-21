#!/bin/sh
# Opens the CocoaPods workspace (required for iOS / MobileVLCKit).
set -e
cd "$(dirname "$0")/.."
if [ ! -d Pods/MobileVLCKit ]; then
  echo "Running pod install…"
  pod install
fi
open EclipsePlexClient.xcworkspace
