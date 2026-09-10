// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// AUTO-GENERATED — edit README.md and run tools/generate_infoview.py to update.

struct InfoView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(BuildInfo.versionAndDate)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Version \(BuildInfo.versionAndDate)")

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
                        Button { withAnimation { proxy.scrollTo("moving-around", anchor: .top) } } label: { Text("Moving around — scrolling through time, and switching screens").frame(maxWidth: .infinity, alignment: .leading) }
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
                    Text("The whole scale runs coldest to hottest:")
                    Image("InfoScaleBar").resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)).accessibilityLabel("The whole comfort scale, coldest at the left through blue, green and yellow to hottest at the right")
                    Text("The column shows a stretch of it at a time, so you can settle on a point precisely:")
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
                    Text("Moving around").font(.headline).id("moving-around")
                    Text("**Swipe left and right to scroll through time.** Both graph screens pan over the same stretch — ten days back and ten days forward — and they share a position, so scrolling to next Tuesday on one and switching to the other keeps you on Tuesday. **Swipe up or down to switch** between the 24-hour and 10-day screens.")
                    Text("The past ten days come from observations rather than the forecast, and arrive a moment after the forecast does. Day labels carry the date once you are away from today, because a bare weekday stops telling you which day you are looking at, and a hollow ring on each curve marks the current hour so \"now\" stays easy to find wherever you have scrolled to.")
                }

                Group {
                    Text("The 10-day screen").font(.headline).id("the-10-day-screen")
                    Text("The same temperature panel stretched over ten days (the recent past drawn dashed), plus a heatmap of your comfort: one column per day, hour-of-day up the side, so the good times of day stand out.")
                    Image("InfoRotation3").resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)).accessibilityLabel("The 10-day heat map: one column per day, hours of the day up the side")
                }

                Group {
                    Text("Reading exact values").font(.headline).id("reading-exact-values")
                    Text("**Long-press any graph** to drop a line you can drag along the timeline. A card shows every value for that moment — your comfort score, temperature and feels like, wet bulb, dew point, wind and gusts, precipitation, cloud and UV. Tap to dismiss.")
                    Image("InfoScrubberReadout").resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)).accessibilityLabel("The long-press readout, with the dashed line marking the hour it describes")
                    DisclosureGroup("Show more — And the table screen") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Because the long-press readout gives you the exact numbers anywhere you point, the full table screen is switched off by default. You can turn it back on in Settings if you like scrolling a full table.")
                            Text("When it is on, the table covers the same twenty days as the graphs and opens on whatever moment the graph was showing, rather than ten days ago. A button at the top of each screen moves between them, and scrolling past either end of the table goes back to the graph.")
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
                    Text("**Comfort scale** offers three ways of showing the same score, for anyone whose color vision makes the default hard to read. **Colors** is the scale above. **No red** keeps every color up to yellow where it is and darkens the hot end to black instead of turning it red, so red/green confusion cannot make a hot hour read as a mild one. **No color** drops hue altogether: the comfort band becomes either a line graph against six named categories — very cold, cold, mild, warm, very warm, hot — or the same band in shades of gray, the rating scale names the categories and shows the number behind them, and the weather curves are told apart by line pattern rather than color.")
                    Text("**Zoom graph** is an alternative to the two graph screens: one screen you pinch to zoom, anywhere from a single day out to ten, with the comfort band turning into the 10-day heat map as you pull out. It holds anywhere mid-turn, scrolls through time like the other screens, and marks the current hour the same way.")
                    DisclosureGroup("Show more — The rest of Settings") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("**Muted colors** softens the weather lines for a gentler look. You can show or hide the **table** screen, turn the weather-sky background on or off, set the name others see when comparing, and choose whether to share anonymous data with the developer.")
                            Text("**Zoom graph** replaces the two graph screens with a single one you **pinch to zoom**: from a 24-hour window out to the full ten days, stopping wherever you like. Swiping left and right scrolls through time as it does everywhere else, and the band turns into the 10-day heat map as you zoom out — part-way is a resting place, mid-turn. Buttons at the top switch to the table.")
                            Image("InfoRotation1").resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)).accessibilityLabel("Before the turn: the comfort band as one horizontal stripe, time of day along its length")
                            Image("InfoRotation2").resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)).accessibilityLabel("Part way through: each day's segment turning")
                            Image("InfoRotation3").resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)).accessibilityLabel("After the turn: a heat map, hours of the day up the side and dates across")
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
                    Text("Link: [Developer documentation on GitHub](https://github.com/dutch-rob/MyFeelsLike/blob/main/ARCHITECTURE.md)")
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
