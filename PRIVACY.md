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

## Comparing with other users

The **Compare** screen lets you see how the same weather would feel to someone
else, by running *your* local forecast through *their* personal model.

**What is shared:** only your **regression model** — a small set of coefficients
plus the model diagnostics needed to fade uncertain predictions — together with
your chosen **compare name**. Your individual **ratings are never shared**, and
no location, coordinates, or place names are included.

**How it is shared (CloudKit public database):** so that a comparison survives
quitting the app, your model is published to the app's CloudKit *public*
database under a **long, random, unguessable share ID** generated on your device
(not derived from your Apple ID). To compare with you, another person must learn
that share ID — either from a **nearby** handshake or a **texted invite link**
(`myfeelslike://compare?id=…`). Records are fetched by their exact name only; the
record type carries **no queryable index**, so the models **cannot be listed or
enumerated** — a share ID works like a secret capability.

- Publishing your own model requires being **signed into iCloud**. If you are
  not, others simply can't see your MyFeelsLike (the app tells you so, and says
  whether it is your iCloud or the other person's that is missing).
- **Nearby** links (Apple's MultipeerConnectivity, over local network /
  Bluetooth) exchange share IDs directly between the two devices; there is no
  intermediary server for the handshake itself.
- **Removing** a saved person forgets them on your device. To withdraw *your
  own* shared model, turn off **Settings ▸ Let others compare with me** — this
  deletes your published record; you can still compare with others.
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
