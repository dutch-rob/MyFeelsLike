//
//  MyFeelsLikeComplication.swift
//  MyFeelsLikeComplication
//
//  Two complications (corner + circular), both driven by the App-Group
//  ComplicationSnapshot the watch app writes after each fetch. The snapshot
//  holds an hourly series of frames, so the timeline emits one entry per hour
//  and the complication advances automatically every hour from already-
//  downloaded forecast data — no new fetch needed between updates.
//
//    • Corner (.accessoryCorner): number = temperature; colour band on the
//      inner arc = the day's feels-like range with the hour's value marked.
//    • Circular (.accessoryCircular): ring gauge, temperature large in centre.
//
//  Colour is the MyFeelsLike gradient once a model exists, else neutral grey.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline

struct FeelsEntry: TimelineEntry {
    let date: Date
    let frame: ComplicationFrame?
    let useFahrenheit: Bool
    let hasModel: Bool
    let sunSplit: Bool
}

struct FeelsProvider: TimelineProvider {
    func placeholder(in context: Context) -> FeelsEntry {
        FeelsEntry(date: .now, frame: nil, useFahrenheit: false, hasModel: false, sunSplit: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (FeelsEntry) -> Void) {
        let snap = ComplicationSnapshot.load()
        completion(FeelsEntry(date: .now, frame: snap?.frames.first,
                              useFahrenheit: snap?.useFahrenheit ?? false,
                              hasModel: snap?.hasModel ?? false,
                              sunSplit: snap?.sunSplit ?? false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FeelsEntry>) -> Void) {
        guard let snap = ComplicationSnapshot.load(), !snap.frames.isEmpty else {
            // No data yet: show a placeholder and try again soon.
            let entry = placeholder(in: context)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
            return
        }
        let now = Date()
        var entries = snap.frames.map { f in
            FeelsEntry(date: f.date, frame: f,
                       useFahrenheit: snap.useFahrenheit, hasModel: snap.hasModel,
                       sunSplit: snap.sunSplit ?? false)
        }
        // Make sure something is valid right now (first frame may be future).
        if let first = entries.first, first.date > now {
            entries.insert(FeelsEntry(date: now, frame: snap.frames.first,
                                      useFahrenheit: snap.useFahrenheit,
                                      hasModel: snap.hasModel,
                                      sunSplit: snap.sunSplit ?? false), at: 0)
        }
        // .atEnd asks for a fresh timeline once the hourly entries run out.
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Shared gauge values

/// Derives the gauge's number, value, range and colour from one frame.
struct FeelsGauge {
    let frame: ComplicationFrame?
    let useFahrenheit: Bool
    let hasModel: Bool
    let sunSplit: Bool

    var tempLabel: String {
        guard let f = frame else { return "--°" }
        let t = useFahrenheit ? f.currentTempC * 9.0 / 5.0 + 32.0 : f.currentTempC
        return "\(Int(t.rounded()))°"
    }

    var range: ClosedRange<Double> {
        guard let f = frame else { return 0...1 }
        let lo = hasModel ? f.feelsMin : f.todayTempMinC
        let hi = hasModel ? f.feelsMax : f.todayTempMaxC
        return hi > lo ? lo...hi : lo...(lo + 1)
    }

    var value: Double {
        guard let f = frame else { return 0.5 }
        let r = range
        let v = hasModel ? f.feelsCurrent : f.currentTempC
        return min(max(v, r.lowerBound), r.upperBound)
    }

    var gradient: Gradient {
        guard let f = frame else { return Gradient(colors: [.gray.opacity(0.5)]) }
        if hasModel {
            let lo = f.feelsMin, hi = max(f.feelsMax, f.feelsMin + 1)
            let n = 5
            let colors = (0..<n).map { i -> Color in
                let score = lo + (hi - lo) * Double(i) / Double(n - 1)
                return ColorScale.color(forScore: score)
            }
            return Gradient(colors: colors)
        } else {
            return Gradient(colors: [.gray.opacity(0.55), .gray.opacity(0.85)])
        }
    }

    /// Fill for the centre disc of the circular complication: the current
    /// MyFeelsLike colour. Nil until a model exists (leave the centre empty).
    var centerColor: Color? {
        guard let f = frame, hasModel else { return nil }
        return ColorScale.color(forScore: f.feelsCurrent)
    }

    /// Split-centre colours (in-sun on top, in-shade below) when the model
    /// learned a sun effect and this frame carries both. Nil ⇒ single centre.
    var centerSunColor: Color? {
        guard hasModel, sunSplit, let s = frame?.feelsSun else { return nil }
        return ColorScale.color(forScore: s)
    }
    var centerShadeColor: Color? {
        guard hasModel, sunSplit, let s = frame?.feelsShade else { return nil }
        return ColorScale.color(forScore: s)
    }

    /// Black or white, whichever reads better on `centerColor`.
    var centerTextColor: Color? {
        guard let f = frame, hasModel else { return nil }
        return ColorScale.contrastingText(forScore: f.feelsCurrent)
    }

    init(_ entry: FeelsEntry) {
        self.frame = entry.frame
        self.useFahrenheit = entry.useFahrenheit
        self.hasModel = entry.hasModel
        self.sunSplit = entry.sunSplit
    }
}

// MARK: - Views

struct FeelsCornerView: View {
    let entry: FeelsEntry
    var body: some View {
        let g = FeelsGauge(entry)
        Text(g.tempLabel)
            .font(.system(size: 50, weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.4)
            .widgetLabel {
                Gauge(value: g.value, in: g.range) { EmptyView() }
                    .tint(g.gradient)
            }
    }
}

struct FeelsCircularView: View {
    let entry: FeelsEntry
    var body: some View {
        let g = FeelsGauge(entry)
        Gauge(value: g.value, in: g.range) {
            EmptyView()
        } currentValueLabel: {
            Text(g.tempLabel)
                .foregroundStyle(g.centerTextColor ?? .primary)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(g.gradient)
        // Fill the centre disc with the current MyFeelsLike colour, inset so
        // the range ring stays visible around it. The temperature sits on top
        // in a contrasting colour. When the model knows a sun effect the disc
        // splits: in-sun on top, in-shade below.
        .background {
            if let sun = g.centerSunColor, let shade = g.centerShadeColor {
                VStack(spacing: 0) {
                    Rectangle().fill(sun)
                    Rectangle().fill(shade)
                }
                .clipShape(Circle())
                .padding(5)
            } else if let c = g.centerColor {
                Circle().fill(c).padding(5)
            }
        }
    }
}

// MARK: - Widgets

struct MyFeelsLikeComplication: Widget {
    let kind = "MyFeelsLikeComplication"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FeelsProvider()) { entry in
            FeelsCornerView(entry: entry)
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
            FeelsCircularView(entry: entry)
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
    FeelsEntry(
        date: .now,
        frame: ComplicationFrame(date: .now, currentTempC: 24, feelsCurrent: 640,
                                 feelsMin: 300, feelsMax: 820,
                                 todayTempMinC: 15, todayTempMaxC: 30,
                                 feelsSun: 780, feelsShade: 480),
        useFahrenheit: false, hasModel: true, sunSplit: true)
    FeelsEntry(date: .now, frame: nil, useFahrenheit: false, hasModel: false, sunSplit: false)
}
