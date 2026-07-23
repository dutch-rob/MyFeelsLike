// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// AUTO-GENERATED — edit README.md and run tools/generate_infoview.py to update.

struct InfoView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                Group {
                    Text("MyFeelsLike learns how the weather actually feels *to you*. Instead of a one-size-fits-all \"feels like\" number, you tell the app how a few moments feel, and it fits a small personal model from your ratings. From then on it shows the forecast as *your* comfort — a color rather than a temperature — across the next 24 hours and 10 days, on iPhone and Apple Watch. You can also compare your comfort with friends nearby, since the same weather can feel quite different to different people.")
                }

                Group {
                    Text("Contents").font(.headline).id("contents")
                    VStack(alignment: .leading, spacing: 8) {
                        Button { withAnimation { proxy.scrollTo("the-colors", anchor: .top) } } label: { Text("The colors — comfort shown as a color, not a number").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("rating-how-it-feels", anchor: .top) } } label: { Text("Rating how it feels — the few taps that teach the app").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("the-24-hour-screen", anchor: .top) } } label: { Text("The 24-hour screen — hourly bands and your comfort band").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("the-10-day-screen", anchor: .top) } } label: { Text("The 10-day screen — the trend and a time-of-day heatmap").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("reading-exact-values", anchor: .top) } } label: { Text("Reading exact values — long-press a graph").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("the-table", anchor: .top) } } label: { Text("The table — every number, if you want it").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("scenarios", anchor: .top) } } label: { Text("Scenarios — activity, clothing, sun or shade").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("comparing-with-others", anchor: .top) } } label: { Text("Comparing with others — nearby, live").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("apple-watch-and-complications", anchor: .top) } } label: { Text("Apple Watch and complications").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("settings-and-units", anchor: .top) } } label: { Text("Settings and units").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("your-data", anchor: .top) } } label: { Text("Your data — what stays on your device").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("more", anchor: .top) } } label: { Text("More — for developers").frame(maxWidth: .infinity, alignment: .leading) }
                    }
                }

                Group {
                    Text("The colors").font(.headline).id("the-colors")
                    Text("Comfort is shown as a color — cool blues and greens through warm yellows to hot reds — so you can read the forecast at a glance without thinking in degrees. The exact colors are whatever *you* rated as comfortable or not. Colors don't appear until you've given the app enough ratings to estimate your MyFeelsLike — usually at least 5.")
                }

                Group {
                    Text("Rating how it feels").font(.headline).id("rating-how-it-feels")
                    Text("Tap **Rate Feels Like** and place how it feels on the color scale, choosing your activity, how you're dressed, and sun or shade for that moment — you set each one deliberately, so nothing is left at a default you didn't mean. A handful of ratings across different conditions is enough to get started; more ratings sharpen it over time.")
                }

                Group {
                    Text("The 24-hour screen").font(.headline).id("the-24-hour-screen")
                    Text("The temperature panel shows the outdoor temperature and the standard apparent-temperature (\"Feels like\") as lines; you can add wet-bulb and dew point, and switch between light **lines** and bold **filled bands**, in Settings. Below it a thin **MyFeelsLike** band shows your predicted comfort hour by hour — split into in-sun and in-shade once the app has learned that sun makes a difference for you — followed by a precipitation and wind panel.")
                }

                Group {
                    Text("The 10-day screen").font(.headline).id("the-10-day-screen")
                    Text("The same temperature panel stretched over ten days (with the recent past drawn dashed), plus a MyFeelsLike heatmap: one column per day, hour-of-day up the side, so the comfortable times of day stand out.")
                }

                Group {
                    Text("Reading exact values").font(.headline).id("reading-exact-values")
                    Text("**Long-press any graph** to drop a line you can drag along the timeline. A small card shows every value for that moment — your MyFeelsLike score, temperature and feels-like, wet-bulb, dew point, wind and gusts, precipitation, cloud, and UV. Tap to dismiss it. Because this gives you the exact numbers wherever you point, the full table screen is optional.")
                }

                Group {
                    Text("The table").font(.headline).id("the-table")
                    Text("Turned off by default (the long-press readout usually covers it), but you can switch it on in Settings: every forecast number in one scrollable place — temperature, feels-like, wet-bulb, dew point, wind and gusts, precipitation, cloud, and UV — hour by hour, with the MyFeelsLike score shown as a number too.")
                }

                Group {
                    Text("Scenarios").font(.headline).id("scenarios")
                    Text("Your comfort depends on what you're doing. Chips let you set your activity, how you're dressed, and sun or shade, and the forecast colors update to match. Only the chips the app has actually learned to use for *you* are shown.")
                }

                Group {
                    Text("Comparing with others").font(.headline).id("comparing-with-others")
                    Text("Compare your MyFeelsLike with other people. When you're together, **Connect Nearby** exchanges your models directly between the two devices for a live comparison. To share with someone who isn't nearby, send them a snapshot of your model — as a link, a small file attachment, or a QR code they scan — with no account or server involved (it even works to an Android device). Either way, the comparison shows as side-by-side color bands for the same weather, so you can see how differently the same day feels to each of you.")
                }

                Group {
                    Text("Apple Watch and complications").font(.headline).id("apple-watch-and-complications")
                    Text("The watch app shows the same 24-hour and 10-day views, and a complication puts your current MyFeelsLike color — split into sun and shade when known — right on your watch face.")
                }

                Group {
                    Text("Settings and units").font(.headline).id("settings-and-units")
                    Text("Choose °C or °F, 12- or 24-hour time, and which forecast series to show. **Chart style** switches the graphs between light lines and filled bands, and **muted** softens the colors for a gentler look. You can show or hide the **table** screen, pick the weather-sky background, set your compare name, and choose whether to share anonymous data with the developer. An experimental **Fold timeline** replaces the two graph screens with a single one you swipe to morph from the 24-hour view into the 10-day heat map.")
                }

                Group {
                    Text("Your data").font(.headline).id("your-data")
                    Text("Your ratings and your personal model stay on your device. They are **not** synced across your devices — each iPhone or iPad keeps its own ratings and its own MyFeelsLike. Nothing leaves your device unless you turn on **Share data with developers** (off by default), which uploads only anonymized ratings and model coefficients — no name, location, or place.")
                }

                Group {
                    Text("More").font(.headline).id("more")
                    Link("Developer documentation on GitHub", destination: URL(string: "https://github.com/dutch-rob/MyFeelsLike/blob/main/ARCHITECTURE.md")!)
                }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Icon before the title echoes the 'i' button users tap
                // to get here, so the connection is obvious.
                Label("Info", systemImage: "info.circle").font(.headline)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .textSelection(.enabled)
    }
}

#Preview {
    NavigationStack {
        InfoView()
    }
}
