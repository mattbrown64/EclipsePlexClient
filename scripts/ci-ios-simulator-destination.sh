#!/usr/bin/env bash
# Prints an xcodebuild -destination for an iPhone simulator compatible with the scheme.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

line=$(
  xcodebuild -showdestinations \
    -workspace "$ROOT/EclipsePlexClient.xcworkspace" \
    -scheme EclipsePlexClient \
    2>/dev/null \
    | grep "platform:iOS Simulator" \
    | grep "name:iPhone" \
    | head -1 \
    || true
)

if [[ -z "$line" ]]; then
  echo "error: no compatible iPhone simulator for EclipsePlexClient" >&2
  xcodebuild -showdestinations \
    -workspace "$ROOT/EclipsePlexClient.xcworkspace" \
    -scheme EclipsePlexClient \
    2>/dev/null \
    | grep "iOS Simulator" \
    | head -20 >&2 || true
  exit 1
fi

id=$(echo "$line" | sed -E 's/.* id:([^,} ]+).*/\1/')
echo "platform=iOS Simulator,id=${id}"
