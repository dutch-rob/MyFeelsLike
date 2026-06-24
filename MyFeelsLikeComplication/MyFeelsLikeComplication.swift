//
//  MyFeelsLikeComplication.swift
//  MyFeelsLikeComplication
//
//  Two complications, both driven by the App-Group ComplicationSnapshot the
//  watch app writes after each fetch:
//
//    • Corner (.accessoryCorner): number = current temperature in the corner;
//      a colour band along the inner arc = today's feels-like range with the
//      current value marked. Number is horizontal so it reads correctly in any
//      of the four corners (WidgetKit can't curve the outer corner element).
//
//    • Circular (.accessoryCircular): a ring gauge with the current temperature
//      large in the centre and the feels-like colour around it. Identical in
//      all four inner slots.
//
//  The colour is the MyFeelsLike gradient once a model exists, otherwise a
//  neutral grey (colouring a narrow temperature range would mislead).
//

import WidgetKit
import SwiftUI

// MARK: - Timeline

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

// MARK: - Shared gauge values

/// Derives the gauge's number, value, range and colour from a snapshot.
/// Shared by the corner and circular complications.
struct FeelsGauge {
    let snapshot: ComplicationSnapshot?

    var tempLabel: String {
        guard let s = snapshot else { return "--°" }
        return "\(s.currentTempDisplay)°"
    }

    var range: ClosedRange<Double> {
        guard let s = snapshot else { return 0...1 }
        let lo: Double = s.hasModel ? s.feelsMin : s.todayTempMinC
        let hi: Double = s.hasModel ? s.feelsMax : s.todayTempMaxC
        return hi > lo ? lo...hi : lo...(lo + 1)   // guard zero-width
    }

    /// Current marker, clamped into the range.
    var value: Double {
        guard let s = snapshot else { return 0.5 }
        let r = range
        let v = s.hasModel ? s.feelsCurrent : s.currentTempC
        return min(max(v, r.lowerBound), r.upperBound)
    }

    var gradient: Gradient {
        guard let s = snapshot else { return Gradient(colors: [.gray.opacity(0.5)]) }
        if s.hasModel {
            let lo = s.feelsMin, hi = max(s.feelsMax, s.feelsMin + 1)
            let n = 5
            let colors = (0..<n).map { i -> Color in
                let score = lo + (hi - lo) * Double(i) / Double(n - 1)
                return ColorScale.color(forScore: score)
            }
            return Gradient(colors: colors)
        } else {
            // No model yet: neutral grey; the dot still shows current position.
            return Gradient(colors: [.gray.opacity(0.55), .gray.opacity(0.85)])
        }
    }
}

// MARK: - Corner view

struct FeelsCornerView: View {
    let snapshot: ComplicationSnapshot?

    var body: some View {
        let g = FeelsGauge(snapshot: snapshot)
        // Horizontal number (reads correctly in any corner) + colour band on
        // the inner arc via widgetLabel.
        Text(g.tempLabel)
            .font(.system(size: 50, weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.4)
            .widgetLabel {
                Gauge(value: g.value, in: g.range) { EmptyView() }
                    .tint(g.gradient)
            }
    }
}

// MARK: - Circular view

struct FeelsCircularView: View {
    let snapshot: ComplicationSnapshot?

    var body: some View {
        let g = FeelsGauge(snapshot: snapshot)
        Gauge(value: g.value, in: g.range) {
            EmptyView()
        } currentValueLabel: {
            Text(g.tempLabel)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(g.gradient)
    }
}

// MARK: - Widgets

struct MyFeelsLikeComplication: Widget {
    let kind = "MyFeelsLikeComplication"
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

struct MyFeelsLikeCircularComplication: Widget {
    let kind = "MyFeelsLikeCircular"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FeelsProvider()) { entry in
            FeelsCircularView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Feels Like")
        .description("Current temperature ringed by today's feels-like range.")
        .supportedFamilies([.accessoryCircular])
    }
}

#Preview(as: .accessoryCircular) {
    MyFeelsLikeCircularComplication()
} timeline: {
    FeelsEntry(date: .now, snapshot: nil)
}
