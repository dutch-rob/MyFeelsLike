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
#         SKY=day tools/make-screenshots.sh                      # daylight background
#         ONLY="iPhone 17" tools/make-screenshots.sh              # just matching devices
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
# "tenday" there is the same picture as "today" and is left out.
# Rate / Places are sheets that don't auto-present via a launch arg — capture
# those by tapping the bottom-bar buttons while running in demo mode.
DEVICES=(
  "352D53EB-F8D7-42D7-90E3-145E9F17E45C|iPhone 17 Pro Max|ios|250000|today scrubber tenday table places rate info"
  "B62C181F-E6F0-4053-859E-42A583057F1E|iPad Pro 13-inch (M5)|ios|250000|today scrubber table rate info"
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
  # Night sky: the daytime background (white clouds on blue) is busier than the
  # graph lines drawn over it. SKY=day for the daylight version.
  local args=(-UITestDemo -UITestSky "${SKY:-night}")
  case "$screen" in
    today)    ;;                                   # the default tab
    # Same screen as "today", with the long-press readout parked mid-chart.
    scrubber) args+=(-UITestScrubber) ;;
    # The table screen is off by default (the long-press readout replaced it),
    # so asking for its tab alone silently lands back on Today.
    table)    args+=(-UITestScreen table -showTable YES) ;;
    *)        args+=(-UITestScreen "$screen") ;;   # tenday, places, rate, info
  esac
  xcrun simctl launch "$udid" "$bundle" "${args[@]}" >/dev/null 2>&1
  local path="$STAGE/${dev}-${idx}_${screen}.png"
  local dest="$OUT/${dev}-${idx}_${screen}.png"
  # Poll until the capture is real content, not the (nearly uniform, small)
  # launch splash. Grab up to ~50s.
  # Sheets keep retrying until SwiftUI accepts them (see presentAfterLaunch),
  # which on a cold device under capture load took ~27s. Don't accept a shot of
  # the screen behind them before that has had time to happen.
  local minwait=9
  case "$screen" in places|rate|info) minwait=36 ;; esac
  local t=0 size=0 prev="" cur="" settled=""
  while [ "$t" -lt 75 ]; do
    xcrun simctl spawn "$udid" sleep 3 >/dev/null 2>&1; t=$((t + 3))
    xcrun simctl io "$udid" screenshot "$path" >/dev/null 2>&1
    if rendered "$path" "$platform" "$threshold" && [ "$t" -ge "$minwait" ]; then
      settled=yes; break
    fi
    # Fallback for screens the size test can't recognise — a sheet of mostly
    # white (Info, Rate) compresses smaller than a launch splash. Once the
    # picture has stopped changing and we are well past a cold launch, take it.
    cur=$(shasum -a1 "$path" 2>/dev/null | cut -d" " -f1)
    if [ -n "$cur" ] && [ "$cur" = "$prev" ] && [ "$t" -ge $((minwait + 15)) ]; then
      settled=yes; break
    fi
    prev="$cur"
  done
  [ -z "$settled" ] && echo "  ! $dev $screen never settled — check it by eye"
  # Let the splash→content cross-fade finish, then keep taking frames until two
  # six seconds apart match. A freshly erased device fires system banners
  # ("Ready for Apple Intelligence") that sit over the UI for a few seconds, and
  # one of those landed square across the iPad's title. Anything transient
  # differs between the two frames; a settled screen does not.
  xcrun simctl spawn "$udid" sleep 5 >/dev/null 2>&1
  local a="" b="" tries=0
  while [ "$tries" -lt 6 ]; do
    xcrun simctl io "$udid" screenshot "$path" >/dev/null 2>&1
    b=$(shasum -a1 "$path" 2>/dev/null | cut -d" " -f1)
    [ -n "$b" ] && [ "$a" = "$b" ] && break
    a="$b"; tries=$((tries + 1))
    xcrun simctl spawn "$udid" sleep 6 >/dev/null 2>&1
  done
  size=$(stat -f%z "$path" 2>/dev/null || echo 0)
  rm -f "$dest"
  cp "$path" "$dest"
  echo "  ✓ $dest  (${t}s, $((size / 1000))KB)"
}

for entry in "${DEVICES[@]}"; do
  IFS='|' read -r udid dev platform threshold screens <<< "$entry"
  # ONLY=<substring> re-runs just the devices whose name matches. One device
  # failing (a simulator caught mid-"Shutting Down" refuses to install, which
  # is how the iPhone got skipped once) should not cost a re-capture of the
  # whole set, especially as every extra erase-and-boot invites the same race.
  if [ -n "${ONLY:-}" ] && [[ "$dev" != *"$ONLY"* ]]; then
    echo "== skipping $dev (ONLY=$ONLY) =="
    continue
  fi
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
  # `shutdown` returns while the device is still "Shutting Down", and erasing or
  # booting in that window fails with SimError 405 — which is how the watch got
  # skipped entirely on one run. Wait for the state to settle first.
  for _ in $(seq 1 30); do
    xcrun simctl list devices | grep -q "$udid.*Shutdown" && break
    sleep 1
  done
  xcrun simctl erase "$udid" >/dev/null 2>&1
  xcrun simctl boot "$udid" >/dev/null 2>&1
  xcrun simctl bootstatus "$udid" >/dev/null 2>&1
  xcrun simctl install "$udid" "$app" || { echo "install failed on $dev"; continue; }
  # No location grant: both apps skip the authorization request entirely in
  # demo mode, so nothing prompts — and granting it lit the location-services
  # arrow in the status bar of every shot.
  # A fixed status bar, the way App Store screenshots normally carry one: full
  # bars, full battery, no carrier clutter, and no location-services arrow.
  # Not supported on watchOS, where it fails harmlessly.
  if [ "$platform" != "watch" ]; then
    xcrun simctl status_bar "$udid" override \
      --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
      --cellularMode active --cellularBars 4 \
      --batteryState charged --batteryLevel 100 >/dev/null 2>&1
  fi
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
