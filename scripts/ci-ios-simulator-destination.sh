#!/usr/bin/env bash
# Prints an xcodebuild -destination for an iOS simulator compatible with the scheme.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

destinations=$(
  xcodebuild -showdestinations \
    -workspace "$ROOT/EclipsePlexClient.xcworkspace" \
    -scheme EclipsePlexClient \
    2>/dev/null \
    | grep "platform:iOS Simulator" \
    | grep -v "placeholder" \
    || true
)

pick() {
  echo "$destinations" | grep "$1" | head -1 || true
}

line=$(pick "name:iPhone")
if [[ -z "$line" ]]; then
  line=$(pick "name:iPad")
fi
if [[ -z "$line" ]]; then
  line=$(echo "$destinations" | head -1)
fi

if [[ -z "$line" ]]; then
  echo "error: no compatible iOS simulator for EclipsePlexClient" >&2
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
