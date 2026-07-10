# Contributing

Thanks for your interest in MyFeelsLike. This is a native SwiftUI iOS + watchOS
app; see [`ARCHITECTURE.md`](ARCHITECTURE.md) for how it fits together.

## Building and running

- **Xcode 16+** (the project uses file-system–synchronized groups).
- An **Apple Developer account** is needed on device because of **WeatherKit**
  (enable the WeatherKit capability on the App ID). **CloudKit** is only used by
  the opt-in *Share data with developers* feature.
- Open `MyFeelsLike.xcodeproj`, pick the **MyFeelsLike** scheme, and run. The
  watch app and complication have their own schemes.

## Tests

```
xcodebuild test -scheme MyFeelsLike \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:MyFeelsLikeTests
```

Unit tests cover the model math and data plumbing (regression fit/selection,
psychrometrics, weather mapping, color scale, scenario gating, export/import,
Codable round-trips). Please keep them green and add tests for new logic.

## The in-app Info screen is generated

`MyFeelsLike/InfoView.swift` is **auto-generated** — do not edit it by hand. Edit
the text between the `<!-- INFO_SCREEN_START -->` / `<!-- INFO_SCREEN_END -->`
markers in [`README.md`](README.md), then run:

```
python3 tools/generate_infoview.py
```

This keeps the README and the in-app Info screen in sync from one source. The
table-of-contents `[label](#anchor)` links become tappable scroll-to buttons in
the app and normal anchors on GitHub.

## Style

- **SwiftUI-first**, value types where possible; keep shared files (see
  ARCHITECTURE) free of app-only dependencies so the watch/complication targets
  keep compiling.
- **US spelling** in code, comments, and UI strings (`color`, `personalize`,
  `center`, `gray`, …). Apple API spellings stay as Apple writes them
  (`Task.isCancelled`).
- Comments explain **why**, not what. Match the surrounding density and idiom.
- Centralize persisted keys in `SettingsKey` / `GraphKey` — don't inline
  `@AppStorage("…")` string literals.
- Log with `os.Logger` (per-file category), not `print`.
- Keep big SwiftUI `body`s split into small computed sub-views (the type-checker
  times out on very large expressions — this bit us once already).

## Commits

- One logical change per commit, with a short imperative subject and a body
  explaining the why.

## Gotchas

- **iCloud Drive**: if the working copy is in iCloud Drive, incremental builds
  can miss edits because iCloud rewrites file modification times. `touch` the
  changed `.swift` files before building if a change doesn't take.
- **Compare / CloudKit** need real devices/accounts to exercise: nearby compare
  needs two devices on the same network; CloudKit needs an iCloud sign-in and the
  paid developer program. Simulators can't fully test either.

## License

By contributing you agree that your contributions are licensed under the
project's **GPL-3.0-or-later** license (see [`LICENSE`](LICENSE)).
