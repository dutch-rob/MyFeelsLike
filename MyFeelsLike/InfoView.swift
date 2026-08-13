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
                    Text("MyFeelsLike learns how the weather actually feels *to you*, and colors the forecast by your own comfort instead of a one-size-fits-all \"feels like\" number. Rate a handful of moments, and from then on the next 24 hours and 10 days are shown as *your* colors — on iPhone and Apple Watch.")
                    Text("**In short:** rate how it feels ▸ the app fits a small personal model ▸ the forecast is colored by your comfort ▸ a thin band means \"don't trust this yet\".")
                    Text("Each section below is a short summary, followed by the detail.")
                }

                Group {
                    Text("Contents").font(.headline).id("contents")
                    VStack(alignment: .leading, spacing: 8) {
                        Button { withAnimation { proxy.scrollTo("the-colors", anchor: .top) } } label: { Text("The colors — comfort as a color, not a number").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("rating-how-it-feels", anchor: .top) } } label: { Text("Rating how it feels — the few taps that teach the app").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("the-24-hour-screen", anchor: .top) } } label: { Text("The 24-hour screen — hourly bands and your comfort band").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("the-10-day-screen", anchor: .top) } } label: { Text("The 10-day screen — the trend and a time-of-day heatmap").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("reading-exact-values", anchor: .top) } } label: { Text("Reading exact values — long-press any graph").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("when-the-band-goes-thin", anchor: .top) } } label: { Text("When the band goes thin — how sure the app is").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("scenarios", anchor: .top) } } label: { Text("Scenarios — activity, clothing, sun or shade").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("comparing-with-others", anchor: .top) } } label: { Text("Comparing with others — nearby, by link or QR").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("apple-watch-and-complications", anchor: .top) } } label: { Text("Apple Watch and complications").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("settings-and-units", anchor: .top) } } label: { Text("Settings and units").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("your-data", anchor: .top) } } label: { Text("Your data — what stays on your device").frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("more", anchor: .top) } } label: { Text("More — for developers").frame(maxWidth: .infinity, alignment: .leading) }
                    }
                }

                Group {
                    Text("The colors").font(.headline).id("the-colors")
                    Text("Comfort is shown as a color — white and blue when it feels cold, green in the middle, yellow through red as it gets hot — so you can read the forecast at a glance without thinking in degrees.")
                    DisclosureGroup("Show more — How the scale works") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("The colors are not tied to fixed temperatures. They are whatever *you* rated as comfortable or not, so the same green can mean 18 °C for one person and 24 °C for another.")
                            Text("Colors only appear once the app has enough ratings to estimate your personal model — usually about five, spread across clearly different weather.")
                            Spacer(minLength: 0)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                }

                Group {
                    Text("Rating how it feels").font(.headline).id("rating-how-it-feels")
                    Text("Tap **Rate Feels Like**, scroll the color column until the strip across the middle shows how this moment feels, then set your activity, clothing and sun/shade. Save.")
                    Image("InfoRatingColumn").resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 380).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)).accessibilityLabel("The rating column, with the ruler marks and the indicator across the middle")
                    DisclosureGroup("Show more — Getting a good model quickly") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("You must set each of the three choices deliberately; nothing is pre-filled, because a default left untouched would teach the app something you did not mean.")
                            Text("Variety matters far more than quantity. Ten ratings all taken in the same hot week teach the app very little, because it cannot tell what came from the temperature and what came from sun, activity or clothing. A handful of ratings across clearly cooler *and* clearly warmer weather is worth much more.")
                            Spacer(minLength: 0)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                }

                Group {
                    Text("The 24-hour screen").font(.headline).id("the-24-hour-screen")
                    Text("The temperature panel shows the outdoor temperature and the standard \"feels like\" as lines. Below it, a band shows your predicted comfort hour by hour; below that, precipitation and wind.")
                    DisclosureGroup("Show more — What else is on this screen") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("You can add wet-bulb and dew point, and switch between light **lines** and bold **filled bands**, in Settings.")
                            Text("Once the app has learned that sun makes a difference for you, the comfort band splits into an in-sun and an in-shade version, so you can see how much shelter is worth on a given day.")
                            Spacer(minLength: 0)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                }

                Group {
                    Text("The 10-day screen").font(.headline).id("the-10-day-screen")
                    Text("The same temperature panel stretched over ten days (the recent past drawn dashed), plus a heatmap of your comfort: one column per day, hour-of-day up the side, so the good times of day stand out.")
                    Image("InfoHeatmap").resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)).accessibilityLabel("The 10-day heat map: one column per day, hours of the day up the side")
                }

                Group {
                    Text("Reading exact values").font(.headline).id("reading-exact-values")
                    Text("**Long-press any graph** to drop a line you can drag along the timeline. A card shows every value for that moment — your comfort score, temperature and feels like, wet bulb, dew point, wind and gusts, precipitation, cloud and UV. Tap to dismiss.")
                    Image("InfoScrubberReadout").resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 380).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)).accessibilityLabel("The long-press readout, with the dashed line marking the hour it describes")
                    DisclosureGroup("Show more — And the table screen") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Because the long-press readout gives you the exact numbers anywhere you point, the full table screen is switched off by default. You can turn it back on in Settings if you like scrolling a full table.")
                            Spacer(minLength: 0)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                }

                Group {
                    Text("When the band goes thin").font(.headline).id("when-the-band-goes-thin")
                    Text("A thin comfort band means the app is *not confident* about that hour, and a short label says why — for example \"colder than you've rated\".")
                    Image("InfoThinBand").resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)).accessibilityLabel("A narrowed comfort band labelled with the reason it is narrow")
                    DisclosureGroup("Show more — Why the app holds back") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Your model only knows the conditions you have actually rated in. A forecast well outside them is guesswork, so instead of showing a confident color the band narrows to a sliver.")
                            Text("Four things can narrow it: an unusual combination of conditions; a value outside the range you rated (temperature, wind, humidity and so on); a scenario you have never rated; or a predicted comfort well outside the range of scores you have ever given.")
                            Text("The cure is always the same — rate a few moments in the kind of weather where the band is thin.")
                            Spacer(minLength: 0)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                }

                Group {
                    Text("Scenarios").font(.headline).id("scenarios")
                    Text("Your comfort depends on what you are doing. The chips at the top set your activity, clothing and sun/shade, and the colors update to match. Only the chips the app has actually learned to use for *you* are shown.")
                }

                Group {
                    Text("Comparing with others").font(.headline).id("comparing-with-others")
                    Text("Compare your colors with other people, for the same weather.")
                    DisclosureGroup("Show more — Three ways to share") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("When you are together, **Connect Nearby** exchanges models directly between the two devices for a live comparison.")
                            Text("For someone who is not nearby, send a snapshot of your model as a link, a small file attachment, or a QR code they scan. No account and no server is involved, and it works to an Android device too. A snapshot does not update when you rate more — re-send it to share a newer one.")
                            Image("InfoShareModel").resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 380).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)).accessibilityLabel("The share sheet: send as a file, or a QR code to scan in person")
                            Text("Either way the comparison shows as side-by-side color bands, so you can see how differently the same day feels to each of you.")
                            Spacer(minLength: 0)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                }

                Group {
                    Text("Apple Watch and complications").font(.headline).id("apple-watch-and-complications")
                    Text("The watch app shows the same 24-hour and 10-day views, and a complication puts your current color — split into sun and shade when known — on your watch face.")
                }

                Group {
                    Text("Settings and units").font(.headline).id("settings-and-units")
                    Text("Choose °C or °F and 12- or 24-hour time, pick which series the graphs show, and switch the chart style between lines and filled bands.")
                    DisclosureGroup("Show more — The rest of Settings") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("**Muted colors** softens the weather lines for a gentler look. You can show or hide the **table** screen, turn the weather-sky background on or off, set the name others see when comparing, and choose whether to share anonymous data with the developer.")
                            Text("**Fold timeline** is experimental: it replaces the two graph screens with a single one you swipe to morph from the 24-hour view into the 10-day heat map. Swipe part-way and it holds there, mid-turn.")
                            Image("InfoFoldRotation").resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)).accessibilityLabel("Mid-swipe: each day's color band turning on its way to becoming a heatmap column")
                            Spacer(minLength: 0)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                }

                Group {
                    Text("Your data").font(.headline).id("your-data")
                    Text("Your ratings and your personal model stay on your device.")
                    DisclosureGroup("Show more — Exactly what goes where") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("They are **not** synced across your devices — each iPhone or iPad keeps its own ratings and its own model.")
                            Text("Nothing leaves your device unless you turn on **Share data with developers** (off by default), which uploads only anonymized ratings and model coefficients — no name, no location, no place.")
                            Spacer(minLength: 0)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
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
