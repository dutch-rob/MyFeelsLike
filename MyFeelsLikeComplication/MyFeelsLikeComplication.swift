//
//  MyFeelsLikeComplication.swift
//  MyFeelsLikeComplication
//
//  Corner complication, à la Apple Weather's temperature corner:
//    • the number = current temperature
//    • a curved gauge along the corner = today's feels-like range, with the
//      current value marked. The gauge uses the MyFeelsLike colour gradient
//      when a model exists, otherwise a neutral temperature gradient.
//      No numbers are shown on the gauge.
//
//  Data comes from the App-Group ComplicationSnapshot the watch app writes
//  after each fetch; the watch app reloads this timeline on every update.
//

import WidgetKit
import SwiftUI

struct FeelsEntry: TimelineEntry {
    let date: Date
    let snapshot: ComplicationSnapshot?
}

struct FeelsProvider: TimelineProvider {
    func placeholder(in context: Context) -> FeelsEntry {
        FeelsEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (FeelsEntry) -> Void) {
        completion(FeelsEntry(date: .now, snapshot: ComplicationSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FeelsEntry>) -> Void) {
        let entry = FeelsEntry(date: .now, snapshot: ComplicationSnapshot.load())
        // The watch app reloads us on each fetch; this is just a fallback.
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct FeelsCornerView: View {
    let snapshot: ComplicationSnapshot?

    var body: some View {
        // Apple Weather layout: large number in the corner; the colour band
        // (gauge) curves along the centre-side bezel via widgetLabel.
        Text(tempLabel)
            .font(.system(size: 30, weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.5)
            .widgetLabel {
                Gauge(value: gaugeValue, in: gaugeRange) { EmptyView() }
                    .tint(gaugeGradient)
            }
    }

    private var tempLabel: String {
        guard let s = snapshot else { return "--°" }
        return "\(s.currentTempDisplay)°"
    }

    /// Clamp the current marker into the gauge's range.
    private var gaugeValue: Double {
        guard let s = snapshot else { return 0.5 }
        let r = gaugeRange
        let v = s.hasModel ? s.feelsCurrent : s.currentTempC
        return min(max(v, r.lowerBound), r.upperBound)
    }

    private var gaugeRange: ClosedRange<Double> {
        guard let s = snapshot else { return 0...1 }
        let lo: Double = s.hasModel ? s.feelsMin : s.todayTempMinC
        let hi: Double = s.hasModel ? s.feelsMax : s.todayTempMaxC
        // Guard against a zero-width range.
        return hi > lo ? lo...hi : lo...(lo + 1)
    }

    private var gaugeGradient: Gradient {
        guard let s = snapshot else {
            return Gradient(colors: [.gray.opacity(0.5)])
        }
        let n = 5
        if s.hasModel {
            // MyFeelsLike colour scale across today's feels-like score range.
            let lo = s.feelsMin, hi = max(s.feelsMax, s.feelsMin + 1)
            let colors = (0..<n).map { i -> Color in
                let score = lo + (hi - lo) * Double(i) / Double(n - 1)
                return ColorScale.color(forScore: score)
            }
            return Gradient(colors: colors)
        } else {
            // Before a model: same colour language, driven by today's
            // temperature range (ColorScale's temperature mapping).
            let lo = s.todayTempMinC, hi = max(s.todayTempMaxC, s.todayTempMinC + 1)
            let colors = (0..<n).map { i -> Color in
                let t = lo + (hi - lo) * Double(i) / Double(n - 1)
                return ColorScale.color(forC: t)
            }
            return Gradient(colors: colors)
        }
    }
}

struct MyFeelsLikeComplication: Widget {
    let kind: String = "MyFeelsLikeComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FeelsProvider()) { entry in
            FeelsCornerView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Feels Like")
        .description("Current temperature with today's feels-like range.")
        .supportedFamilies([.accessoryCorner])
    }
}

#Preview(as: .accessoryCorner) {
    MyFeelsLikeComplication()
} timeline: {
    FeelsEntry(date: .now, snapshot: nil)
}
