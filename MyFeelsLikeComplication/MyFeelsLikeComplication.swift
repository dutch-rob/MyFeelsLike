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
        Text(tempLabel)
            .font(.system(.title3, design: .rounded).weight(.medium))
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
        guard let s = snapshot, s.hasModel else {
            // Neutral cold→hot gradient for the cold-start (no-model) case.
            return Gradient(colors: [.blue, .green, .yellow, .orange, .red])
        }
        // Sample the MyFeelsLike colour scale across today's feels-like range.
        let n = 5
        let lo = s.feelsMin, hi = max(s.feelsMax, s.feelsMin + 1)
        let colors = (0..<n).map { i -> Color in
            let score = lo + (hi - lo) * Double(i) / Double(n - 1)
            return ColorScale.color(forScore: score)
        }
        return Gradient(colors: colors)
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
