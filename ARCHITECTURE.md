# Architecture

A technical overview of how MyFeelsLike is put together, for contributors. For
the user-facing description see [`README.md`](README.md); for data handling see
[`PRIVACY.md`](PRIVACY.md).

## Targets

| Target | Folder | Notes |
|---|---|---|
| `MyFeelsLike` (iOS app) | `MyFeelsLike/` | SwiftUI, SwiftData, WeatherKit, CloudKit |
| `MyFeelsLike Watch App` (watchOS app) | `MyFeelsLike Watch App Watch App/` | fetches its own weather |
| `MyFeelsLikeComplication` (widget ext.) | `MyFeelsLikeComplication/` | watch-face complications |
| `MyFeelsLikeTests` (unit) / `…UITests` | `MyFeelsLikeTests/`, `MyFeelsLikeUITests/` | |

The project uses Xcode 16 **file-system–synchronized groups**: files in a
target's folder are members automatically. A handful of pure value/logic files
are shared into the watch and complication targets via `membershipExceptions`
in `project.pbxproj` (e.g. `ForecastPoint.swift`, `ColorScale.swift`,
`ComplicationSnapshot.swift`, `FeelsLikeInference.swift`, `WeatherMapping.swift`,
`Psychrometrics.swift`, `WatchSyncPayload.swift`). Keep shared files free of
UIKit-only or app-only dependencies.

## Data flow (weather → screen)

```
WeatherKit ─▶ WeatherService ─▶ [ForecastPoint] ─▶ views (charts/table)
                    │                  ▲
              WeatherMapping           │ applyPrediction(state:scenario:)
              (+ Psychrometrics        │
               for wet-bulb)     RegressionState (personal model)
```

- **`ForecastPoint`** (`ForecastPoint.swift`) — one hour of weather plus the
  personalized fields (`myFeelsLikeScore`, `myFeelsLikeOpacity`, and the sun/shade
  variants). Pure `Codable` value type, shared across targets.
- **`WeatherService`** — `@MainActor ObservableObject`; fetches and maps the
  forecast, exposes `series24h`, `series10d`, `current`, `historic`, sun times,
  attribution, and load progress.
- **`WeatherMapping`** maps WeatherKit models into `ForecastPoint`, deriving
  wet-bulb via `PsychrometryCalculator` and station pressure from altitude.

## The personal-comfort model

The heart of the app. A user's ratings are fit into a small linear model whose
prediction is rendered as a color.

- **`Rating`** (`Rating.swift`, SwiftData `@Model`) — one comfort rating: the
  `feelsLikeScore` (0–1000 target), the `activity`/`dress`/`sun` scenario, and the
  weather snapshot at that moment.
- **`FeelsLikeRegression`** (`FeelsLikeRegression.swift`) — forward feature
  selection by AICc over candidate features, each fit by OLS on standardized
  features (Cholesky solve of the normal equations). Produces a `RegressionState`.
- **`RegressionState`** (`FeelsLikeInference.swift`) — the fitted model:
  `selectedFeatures`, `coefficients`, feature `means`/`stds`, `rSquared`, `aicc`,
  `ratingCount`, and `invXtX` (for leverage). `predict(_:)` gives the score;
  `predictionOpacity(_:)` fades the color where the forecast extrapolates beyond
  the training distribution (leverage-based).
- **`ForecastPoint.applyPrediction(state:scenario:)`** writes the score/opacity
  onto a point (sanitized to finite values); `applySunShadePrediction` computes
  the in-sun/in-shade split used by the 24h band and the complication.

`ContentView` owns the current `RegressionState`, refits on rating changes
(`refitRegression()`), and persists it via `RegressionStateStore` (UserDefaults).

## Color

`ColorScale` (`ColorScale.swift`) maps a 0–1000 score to a color using
temperature-derived anchors warped along the scale, matching the Rate screen's
gradient exactly. `ColorScale.feelsColor(score:opacity:)` is the single source of
truth for band/heatmap/complication cell colors (finite-safe).

## UI structure (iOS)

- **`ContentView`** — the shell: title bar, the whole-screen weather-sky
  background (`WeatherSky.swift`), the bottom toolbar, and the paged forecast
  content. Uses a **phantom-tab circular pager** (extra duplicate tabs that
  teleport, so swiping wraps around). Also hosts the Compare screen and the
  sheets. `body` is deliberately split into small computed sub-views to keep the
  type-checker fast.
- **`HereTodayView`** (24h), **`TenDayView`** (10-day), **`ForecastTableView`**
  (table), **`ScenarioStrip`** (activity/dress/sun chips), **`RateFeelsLikeView`**
  (rating), **`CompareView`** (compare screen). Shared pieces (legend, loading
  view, color helpers, `GraphKey`) live in `SharedChartComponents.swift`.
- Charts use Swift Charts; temperature is drawn as baseline-to-curve `AreaMark`
  bands (so a series still reaches the axis when others are toggled off).

## Sync paths

Four independent channels — see also `PRIVACY.md`.

1. **Phone → Watch** (`PhoneWatchSync.swift`, WatchConnectivity): pushes the
   model + display settings + saved places to the watch (`WatchSyncPayload`).
   The watch never sends forecast data back; it fetches its own.
2. **Watch → Complication** (`ComplicationSnapshot.swift` via an App Group):
   `WatchComplicationWriter` builds an hourly snapshot; the complication reads it
   and advances hourly without refetching.
3. **Nearby Compare** (`NearbyCompare.swift`, MultipeerConnectivity): one
   `MCSession` per peer so each link has its own lifetime; peers exchange only
   `RegressionState` + name; peer models are in-memory and dropped on link end.
4. **Developer data sharing** (`DeveloperDataSync.swift`, CloudKit public DB):
   opt-in; uploads anonymized `SharedRating`/`SharedModel` records keyed by a
   random per-install id; opting out deletes them.

## Persistence

- **SwiftData**: `Rating` (in-memory store in demo/screenshot mode).
- **UserDefaults**: settings (`SettingsKey`, `GraphKey`), the fitted model
  (`RegressionStateStore`), the compare name, the developer-share install id.
- Ratings/model are **device-local** — not synced across a user's devices.

## Conventions worth knowing

- Colors/spelling: US English throughout; Apple API spellings kept
  (`Task.isCancelled`).
- The 0–1000 score scale is internal; the UI shows color (the table also shows
  the number as a check).
- The in-app **Info** screen is generated from `README.md` — see
  [`CONTRIBUTING.md`](CONTRIBUTING.md).
- **iCloud Drive build quirk**: if the repo lives in iCloud Drive, `touch`
  changed `.swift` files before building (iCloud rewrites mtimes and confuses
  incremental builds).
