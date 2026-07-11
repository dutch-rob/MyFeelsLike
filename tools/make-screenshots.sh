#!/bin/bash
# App Store screenshots via simctl (reliable on Xcode 26, where fastlane
# snapshot 2.236.x crashes on the new simctl JSON — device.devicetype.name).
#
# Builds nothing itself: build the MyFeelsLike scheme for an iOS Simulator first
# (Xcode or `xcodebuild build`), then run this. It drives the app's demo mode +
# the -UITestScreen launch arg to reach each screen and captures with
# `simctl io screenshot`, writing to fastlane/screenshots/en-US with the same
# "<Device>-NN_name.png" naming fastlane used.
#
# Usage:  tools/make-screenshots.sh
set -uo pipefail
cd "$(dirname "$0")/.."

BUNDLE="robotex.MyFeelsLike"
OUT="fastlane/screenshots/en-US"
SETTLE="${SETTLE:-22}"          # seconds to let a cold launch finish rendering
mkdir -p "$OUT"

APP=$(find ~/Library/Developer/Xcode/DerivedData/MyFeelsLike-*/Build/Products/Debug-iphonesimulator \
        -maxdepth 1 -name "MyFeelsLike.app" 2>/dev/null | head -1)
if [ -z "$APP" ]; then echo "MyFeelsLike.app not found — build the scheme first."; exit 1; fi
echo "Using app: $APP"

# device UDID | display name (used in the filename)
DEVICES=(
  "352D53EB-F8D7-42D7-90E3-145E9F17E45C|iPhone 17 Pro Max"
  "B62C181F-E6F0-4053-859E-42A583057F1E|iPad Pro 13-inch (M5)"
)
SCREENS=(today tenday table rate places)

shoot() {   # udid  devname  index  screen
  local udid="$1" dev="$2" idx="$3" screen="$4"
  xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1
  local args=(-UITestDemo)
  [ "$screen" != "today" ] && args+=(-UITestScreen "$screen")
  xcrun simctl launch "$udid" "$BUNDLE" "${args[@]}" >/dev/null 2>&1
  local path="$OUT/${dev}-${idx}_${screen}.png"
  # Poll until the capture is real content, not the (nearly uniform, small)
  # launch splash. Every app screen — sky background, charts, forms — encodes to
  # well over 250 KB; a splash is under ~170 KB. Grab up to ~50s.
  local t=0 size=0
  while [ "$t" -lt 50 ]; do
    xcrun simctl spawn "$udid" sleep 3 >/dev/null 2>&1; t=$((t + 3))
    xcrun simctl io "$udid" screenshot "$path" >/dev/null 2>&1
    size=$(stat -f%z "$path" 2>/dev/null || echo 0)
    [ "$size" -gt 250000 ] && [ "$t" -ge 9 ] && break
  done
  # Let the splash→content cross-fade finish, then take the final frame.
  xcrun simctl spawn "$udid" sleep 5 >/dev/null 2>&1
  xcrun simctl io "$udid" screenshot "$path" >/dev/null 2>&1
  size=$(stat -f%z "$path" 2>/dev/null || echo 0)
  echo "  ✓ $path  (${t}s, $((size / 1000))KB)"
}

for pair in "${DEVICES[@]}"; do
  udid="${pair%%|*}"; dev="${pair##*|}"
  echo "== $dev =="
  xcrun simctl boot "$udid" >/dev/null 2>&1
  xcrun simctl bootstatus "$udid" >/dev/null 2>&1
  xcrun simctl uninstall "$udid" "$BUNDLE" >/dev/null 2>&1
  xcrun simctl install "$udid" "$APP" || { echo "install failed on $dev"; continue; }
  # Warm-up launch so the first real capture isn't a cold-start splash.
  xcrun simctl launch "$udid" "$BUNDLE" -UITestDemo >/dev/null 2>&1
  xcrun simctl spawn "$udid" sleep 25 >/dev/null 2>&1
  i=1
  for screen in "${SCREENS[@]}"; do
    printf -v idx "%02d" "$i"
    shoot "$udid" "$dev" "$idx" "$screen"
    i=$((i + 1))
  done
done
echo "Screenshots written to $OUT"
