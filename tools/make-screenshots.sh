#!/bin/bash
# App Store screenshots via simctl (reliable on Xcode 26, where fastlane
# snapshot 2.236.x crashes on the new simctl JSON — device.devicetype.name).
#
# Builds nothing itself: build the MyFeelsLike scheme for an iOS Simulator and
# the "MyFeelsLike Watch App Watch App" scheme for a watchOS Simulator first
# (Xcode or `xcodebuild build`), then run this. It drives the apps' demo mode +
# the -UITestScreen launch arg to reach each screen and captures with
# `simctl io screenshot`, writing to fastlane/screenshots/en-US with the same
# "<Device>-NN_name.png" naming fastlane used.
#
# Usage:  tools/make-screenshots.sh
#         DERIVED_DATA=/path/to/dd tools/make-screenshots.sh     # non-default build dir
set -uo pipefail
cd "$(dirname "$0")/.."

BUNDLE="robotex.MyFeelsLike"
WATCH_BUNDLE="robotex.MyFeelsLike.watchkitapp"
OUT="fastlane/screenshots/en-US"
mkdir -p "$OUT"
# Capture to local scratch first, then copy in. This repo lives in iCloud
# Drive, and writing a screenshot straight over an existing synced file left
# the old bytes in place — three runs in a row "succeeded" while producing
# byte-identical files that showed a previous session's settings. Staging
# outside iCloud and replacing the destination avoids that entirely.
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/mfl-shots.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

# Where to look for the built .app bundles. DERIVED_DATA overrides, which is
# what you want when the repo lives in iCloud Drive and builds go elsewhere.
if [ -n "${DERIVED_DATA:-}" ]; then
  SEARCH=("$DERIVED_DATA/Build/Products")
else
  SEARCH=(~/Library/Developer/Xcode/DerivedData/MyFeelsLike-*/Build/Products)
fi

find_app() {   # subdir  appname
  find "${SEARCH[@]}" -maxdepth 2 -path "*/$1/$2" -print 2>/dev/null | head -1
}

APP=$(find_app "Debug-iphonesimulator" "MyFeelsLike.app")
[ -z "$APP" ] && APP=$(find_app "Release-iphonesimulator" "MyFeelsLike.app")
if [ -z "$APP" ]; then echo "MyFeelsLike.app not found — build the iOS scheme first."; exit 1; fi
echo "Using iOS app:   $APP"

WATCH_APP=$(find_app "Debug-watchsimulator" "MyFeelsLike Watch App Watch App.app")
[ -z "$WATCH_APP" ] && WATCH_APP=$(find_app "Release-watchsimulator" "MyFeelsLike Watch App Watch App.app")
if [ -n "$WATCH_APP" ]; then echo "Using watch app: $WATCH_APP"
else echo "No watch app build found — skipping Apple Watch (build the watch scheme to include it)."; fi

# udid | display name | platform | "this is real content" threshold | screens.
# See rendered() for what the threshold is measured against — it differs by
# platform, so the two are set together.
#
# The iPad shows the 24-hour and 10-day panes side by side in one layout, so
# "tenday" there is the same picture as "today", and its table screen isn't
# presentable (with the sky hidden the graph legends draw white-on-white) — one
# capture covers the iPad.
# Rate / Places are sheets that don't auto-present via a launch arg — capture
# those by tapping the bottom-bar buttons while running in demo mode.
DEVICES=(
  "352D53EB-F8D7-42D7-90E3-145E9F17E45C|iPhone 17 Pro Max|ios|250000|today tenday table"
  "B62C181F-E6F0-4053-859E-42A583057F1E|iPad Pro 13-inch (M5)|ios|250000|today"
  "360294D4-8EB4-4D83-AA6E-424D38B6B77C|Apple Watch Series 11 (46mm)|watch|3000|today tenday table"
)

# Has the capture finished rendering, or is it still the launch splash?
#   ios   — whole-file size. Every real screen (sky background, charts, forms)
#           encodes well past 250 KB; a splash stays under ~170 KB.
#   watch — file size does NOT separate them: a watch splash and a sparse black
#           chart screen are both ~20-40 KB. What does separate them is the band
#           just below the status bar, which is pure black on the splash (the
#           icon sits lower) and carries the title on every real screen. Pure
#           black re-encodes to ~1.8 KB, real content to 7 KB and up.
rendered() {   # path  platform  threshold
  local path="$1" platform="$2" threshold="$3" bytes
  if [ "$platform" = "watch" ]; then
    local strip="${TMPDIR:-/tmp}/mfl-strip.png"
    sips -c 120 416 --cropOffset 30 0 "$path" --out "$strip" >/dev/null 2>&1 || return 1
    bytes=$(stat -f%z "$strip" 2>/dev/null || echo 0)
  else
    bytes=$(stat -f%z "$path" 2>/dev/null || echo 0)
  fi
  [ "$bytes" -gt "$threshold" ]
}

shoot() {   # udid  devname  index  screen  bundle  threshold  platform
  local udid="$1" dev="$2" idx="$3" screen="$4" bundle="$5" threshold="$6" platform="$7"
  xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1
  local args=(-UITestDemo)
  [ "$screen" != "today" ] && args+=(-UITestScreen "$screen")
  # The table screen is off by default on the phone/iPad (the long-press
  # readout replaced it), so asking for its tab alone silently lands back on
  # Today — turn it on for that one capture.
  [ "$screen" = "table" ] && args+=(-showTable YES)
  xcrun simctl launch "$udid" "$bundle" "${args[@]}" >/dev/null 2>&1
  local path="$STAGE/${dev}-${idx}_${screen}.png"
  local dest="$OUT/${dev}-${idx}_${screen}.png"
  # Poll until the capture is real content, not the (nearly uniform, small)
  # launch splash. Grab up to ~50s.
  local t=0 size=0
  while [ "$t" -lt 60 ]; do
    xcrun simctl spawn "$udid" sleep 3 >/dev/null 2>&1; t=$((t + 3))
    xcrun simctl io "$udid" screenshot "$path" >/dev/null 2>&1
    rendered "$path" "$platform" "$threshold" && [ "$t" -ge 9 ] && break
  done
  if ! rendered "$path" "$platform" "$threshold"; then
    echo "  ! $dev $screen still looks like the launch splash after ${t}s"
  fi
  # Let the splash→content cross-fade finish, then take the final frame.
  xcrun simctl spawn "$udid" sleep 5 >/dev/null 2>&1
  xcrun simctl io "$udid" screenshot "$path" >/dev/null 2>&1
  size=$(stat -f%z "$path" 2>/dev/null || echo 0)
  rm -f "$dest"
  cp "$path" "$dest"
  echo "  ✓ $dest  (${t}s, $((size / 1000))KB)"
}

for entry in "${DEVICES[@]}"; do
  IFS='|' read -r udid dev platform threshold screens <<< "$entry"
  if [ "$platform" = "watch" ]; then
    [ -z "$WATCH_APP" ] && continue
    app="$WATCH_APP"; bundle="$WATCH_BUNDLE"
  else
    app="$APP"; bundle="$BUNDLE"
  fi
  echo "== $dev =="
  # Erase, don't just uninstall. A leftover container carries the previous
  # session's settings (which series the graphs show, chart style) and its saved
  # model, and those quietly change what the screenshots look like — one run
  # came out with four series and a full-width band instead of the demo's two
  # and a narrowed one. A stuck permission alert survives an uninstall too.
  # Erasing costs a slower first boot and buys reproducible captures.
  xcrun simctl shutdown "$udid" >/dev/null 2>&1
  xcrun simctl erase "$udid" >/dev/null 2>&1
  xcrun simctl boot "$udid" >/dev/null 2>&1
  xcrun simctl bootstatus "$udid" >/dev/null 2>&1
  xcrun simctl install "$udid" "$app" || { echo "install failed on $dev"; continue; }
  # Demo mode never asks for a location, but pre-granting costs nothing and
  # keeps a stray permission alert off the captures.
  xcrun simctl privacy "$udid" grant location "$bundle" >/dev/null 2>&1
  # Warm-up launch so the first real capture isn't a cold-start splash.
  xcrun simctl launch "$udid" "$bundle" -UITestDemo >/dev/null 2>&1
  xcrun simctl spawn "$udid" sleep 25 >/dev/null 2>&1
  i=1
  for screen in $screens; do
    printf -v idx "%02d" "$i"
    shoot "$udid" "$dev" "$idx" "$screen" "$bundle" "$threshold" "$platform"
    i=$((i + 1))
  done
done
echo "Screenshots written to $OUT"
