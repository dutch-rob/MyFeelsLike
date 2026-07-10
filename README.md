# MyFeelsLike

<!-- INFO_SCREEN_START -->
MyFeelsLike learns how the weather actually feels *to you*. Instead of a
one-size-fits-all "feels like" number, you tell the app how a few moments feel,
and it fits a small personal model from your ratings. From then on it shows the
forecast as *your* comfort — a color rather than a temperature — across the next
24 hours and 10 days, on iPhone and Apple Watch. You can also compare your
comfort with friends nearby, since the same weather can feel quite different to
different people.

## Contents
- [The colors](#the-colors) — comfort shown as a color, not a number
- [Rating how it feels](#rating-how-it-feels) — the few taps that teach the app
- [The 24-hour screen](#the-24-hour-screen) — hourly bands and your comfort band
- [The 10-day screen](#the-10-day-screen) — the trend and a time-of-day heatmap
- [The table](#the-table) — every number, if you want it
- [Scenarios](#scenarios) — activity, clothing, sun or shade
- [Comparing with others](#comparing-with-others) — nearby, live
- [Apple Watch and complications](#apple-watch-and-complications)
- [Settings and units](#settings-and-units)
- [Your data](#your-data) — what stays on your device
- [More](#more) — for developers

## The colors
Comfort is shown as a color — cool blues and greens through warm yellows to hot
reds — so you can read the forecast at a glance without thinking in degrees. The
exact colors are whatever *you* rated as comfortable or not. Colors don't appear
until you've given the app enough ratings to estimate your MyFeelsLike — usually
at least 5.

## Rating how it feels
Tap **Rate Feels Like** and place how it feels on the color scale, with optional
notes on your activity, how you're dressed, and sun or shade. A handful of
ratings across different conditions is enough to get started; more ratings sharpen
it over time.

## The 24-hour screen
Filled bands show temperature, wet-bulb, and dew point, with the standard
apparent-temperature ("Feels like") line on top. Below them, a thin **MyFeelsLike**
band shows your predicted comfort hour by hour — split into in-sun and in-shade
once the app has learned that sun makes a difference for you.

## The 10-day screen
The same temperature bands stretched over ten days (with the recent past drawn
dashed), plus a MyFeelsLike heatmap: one column per day, hour-of-day up the side,
so the comfortable times of day stand out.

## The table
Every forecast number in one place — temperature, feels-like, wet-bulb, dew point,
wind and gusts, precipitation, cloud, and UV — hour by hour. The MyFeelsLike score
is also shown as a number here, mainly as a check for those who like exact figures.

## Scenarios
Your comfort depends on what you're doing. Chips let you set your activity, how
you're dressed, and sun or shade, and the forecast colors update to match. Only
the chips the app has actually learned to use for *you* are shown.

## Comparing with others
Compare your MyFeelsLike with people near you. Open **Compare**, tap **Connect
Nearby**, and invite someone — or accept their invite — for one hour or until one
of you cancels. Your models are exchanged directly between the two devices and
shown as side-by-side color bands for the same weather, so you can see how
differently the same day feels to each of you.

## Apple Watch and complications
The watch app shows the same 24-hour and 10-day views, and a complication puts
your current MyFeelsLike color — split into sun and shade when known — right on
your watch face.

## Settings and units
Choose °C or °F, 12- or 24-hour time, which graphs to show, the weather-sky
background, your compare name, and whether to share anonymous data with the
developer.

## Your data
Your ratings and your personal model stay on your device. They are **not** synced
across your devices — each iPhone or iPad keeps its own ratings and its own
MyFeelsLike. Nothing leaves your device unless you turn on **Share data with
developers** (off by default), which uploads only anonymized ratings and model
coefficients — no name, location, or place.

## More
[Developer documentation on GitHub](https://github.com/dutch-rob/MyFeelsLike/blob/main/ARCHITECTURE.md)
<!-- INFO_SCREEN_END -->

---

## Building it yourself

MyFeelsLike is a native SwiftUI app for iOS + watchOS.

**Requirements**
- Xcode 16 or later (the project uses file-system–synchronized groups).
- An Apple Developer account, because the app uses **WeatherKit** (enable the
  WeatherKit capability on the App ID) and, for the optional data-sharing
  feature, **CloudKit**.

**Run it**
1. Open `MyFeelsLike.xcodeproj`.
2. Select the **MyFeelsLike** scheme and a simulator or device, and run. The
   watch app and the complication build from their own schemes.

**Capabilities**
- **WeatherKit** — required; the app fetches forecasts from Apple.
- **App Groups** (`group.robotex.MyFeelsLike`) — shares the complication snapshot
  between the watch app and its complication.
- **CloudKit** (`iCloud.robotex.MyFeelsLike`, phone target only) — only used when
  a user opts in to *Share data with developers*.

**Note (iCloud Drive):** if you keep the repo in iCloud Drive, incremental builds
can miss changes because iCloud rewrites file timestamps — `touch` the changed
`.swift` files before building if a change doesn't seem to take.

## Architecture and contributing

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — how the app is put together (data flow,
  the personal-comfort model, the sync paths).
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — conventions, tests, and how to work on it.
- [`PRIVACY.md`](PRIVACY.md) — exactly what data the app handles and where it goes.

The in-app **Info** screen (Settings ▸ Info) is generated from the section of this
file between the `INFO_SCREEN` markers — edit the text here and run
`python3 tools/generate_infoview.py` to regenerate `MyFeelsLike/InfoView.swift`.

## License

MyFeelsLike is licensed under the **GNU General Public License v3.0 or later**.
See [`LICENSE`](LICENSE).
