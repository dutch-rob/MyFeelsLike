# Privacy

MyFeelsLike is designed to keep your data on your device. This document
describes exactly what data the app handles and where it goes.

## On device by default

Everything the app needs works locally:

- **Your ratings** (how the weather felt to you) and the **personalized model**
  fitted from them are stored on your device (SwiftData) and in the app's
  preferences. They are not sent anywhere unless you explicitly opt in (see
  *Sharing with the developer* below).
- **Settings** (units, which graphs to show, your compare name, etc.) are stored
  locally in the app's preferences.

## Weather data

The app uses **Apple WeatherKit** to fetch forecasts. To do this it sends the
relevant **location** (your current location or a place you chose) to Apple in
order to receive the weather for that location. This is handled by Apple and
governed by [Apple's privacy policy](https://www.apple.com/legal/privacy/).
WeatherKit attribution and a link to Apple's data sources are shown in the app.

## Comparing with other users (nearby)

When you use **Compare ▸ Connect Nearby**, two devices connect directly over the
local network / Bluetooth (Apple's MultipeerConnectivity) — there is no server:

- Only your **regression model** (a small set of coefficients) and your chosen
  **compare name** are exchanged. Your individual ratings are **not** sent.
- A peer's model is held **in memory only** while the link is alive and is
  **deleted when the link ends** (after one hour, or when either person cancels).
- Data received from a peer is **never** included in anything shared with the
  developer.

## Sharing with the developer (opt-in, off by default)

**Settings ▸ Share data with developers** is off unless you turn it on. When on,
the app uploads, to the app's CloudKit public database:

- your **ratings** — the feels-like score, your activity/dress/sun selection, and
  the **weather snapshot** at that moment;
- your **model coefficients**.

It is **anonymised**: records are tagged only with a **random per-install
identifier**. No name, no location or coordinates, and no place names are
included. Only the developer can read the full set (each user can read only their
own rows). **Turning the setting off deletes everything this install uploaded.**

## No third-party tracking

The app contains **no third-party analytics, advertising, or tracking SDKs**.
The only network services it uses are Apple's (WeatherKit, and — only if you opt
in — CloudKit).
