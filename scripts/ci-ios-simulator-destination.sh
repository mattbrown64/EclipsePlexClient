#!/usr/bin/env bash
# Prints an xcodebuild -destination for an iOS simulator compatible with the scheme.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

xcodebuild_args=(
  -showdestinations
  -workspace "$ROOT/EclipsePlexClient.xcworkspace"
  -scheme EclipsePlexClient
  -sdk iphonesimulator
  DEVELOPMENT_TEAM=
  CODE_SIGN_STYLE=Manual
  CODE_SIGN_IDENTITY=-
  CODE_SIGNING_REQUIRED=NO
)

destinations=$(
  xcodebuild "${xcodebuild_args[@]}" 2>/dev/null \
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
  # Fallback: first bootable iOS 26+ simulator from simctl.
  udid=$(
    python3 - <<'PY'
import json, subprocess, re
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
best = None
for runtime, devices in data.get("devices", {}).items():
    m = re.search(r"iOS[- ](\d+)", runtime)
    if not m or int(m.group(1)) < 26:
        continue
    for device in devices:
        if not device.get("isAvailable", True):
            continue
        name = device.get("name", "")
        if "iPhone" in name or "iPad" in name:
            best = device["udid"]
            if "iPhone" in name:
                break
    if best:
        break
if best:
    print(best)
PY
  )
  if [[ -n "${udid:-}" ]]; then
    echo "platform=iOS Simulator,id=${udid}"
    exit 0
  fi

  echo "error: no compatible iOS simulator for EclipsePlexClient" >&2
  xcodebuild "${xcodebuild_args[@]}" 2>/dev/null | grep "iOS Simulator" | head -20 >&2 || true
  exit 1
fi

id=$(echo "$line" | sed -E 's/.* id:([^,} ]+).*/\1/')
echo "platform=iOS Simulator,id=${id}"
