// SPDX-License-Identifier: GPL-3.0-or-later
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
//    • Corner (.accessoryCorner): number = temperature; color band on the
//      inner arc = the day's feels-like range with the hour's value marked.
//    • Circular (.accessoryCircular): ring gauge, temperature large in center.
//
//  Color is the MyFeelsLike gradient once a model exists, else neutral gray.
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

/// Derives the gauge's number, value, range and color from one frame.
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

    /// Position of the current value within the day's range, 0…1.
    var fraction: Double {
        let r = range
        let span = r.upperBound - r.lowerBound
        return span > 0 ? (value - r.lowerBound) / span : 0.5
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

    /// Fill for the center disc of the circular complication: the current
    /// MyFeelsLike color. Nil until a model exists (leave the center empty).
    var centerColor: Color? {
        guard let f = frame, hasModel else { return nil }
        return ColorScale.color(forScore: f.feelsCurrent)
    }

    /// Split-center colors (in-sun on top, in-shade below) when the model
    /// learned a sun effect and this frame carries both. Nil ⇒ single center.
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
        return ColorScale.isLight(forScore: f.feelsCurrent) ? .black : .white
    }

    /// The opposite of `centerTextColor`, used as a thin outline so the number
    /// stays legible over either half of a split sun/shade disc.
    var centerOutlineColor: Color? {
        guard let f = frame, hasModel else { return nil }
        return ColorScale.isLight(forScore: f.feelsCurrent) ? .white : .black
    }

    init(_ entry: FeelsEntry) {
        self.frame = entry.frame
        self.useFahrenheit = entry.useFahrenheit
        self.hasModel = entry.hasModel
        self.sunSplit = entry.sunSplit
    }
}

// MARK: - Views

/// Text with a thin contrasting outline, so the number stays readable over a
/// two-tone (sun/shade) disc where a single fill color can't contrast with both
/// halves. Draws the outline color in eight directions behind the fill.
private struct OutlinedText: View {
    let text: String
    let fill: Color
    let outline: Color
    var width: CGFloat = 0.7

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) / 8.0 * 2.0 * .pi
                Text(text)
                    .foregroundStyle(outline)
                    .offset(x: width * CGFloat(cos(angle)), y: width * CGFloat(sin(angle)))
            }
            Text(text).foregroundStyle(fill)
        }
    }
}

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

/// A circular range gauge (like the weather app): an open ~270° arc tinted with
/// the day's whole MyFeelsLike range, a marker at the current value, and custom
/// content in the center. Replaces the stock Gauge, which only fills min→now and
/// so can't show the full range.
private struct RangeGauge<Center: View>: View {
    let gradient: Gradient
    let fraction: Double            // 0…1 position of "now" within the range
    var lineWidth: CGFloat = 5
    @ViewBuilder var center: () -> Center

    private let gapDegrees = 90.0
    private var sweep: Double { 360 - gapDegrees }            // 270° arc
    private var startDegrees: Double { 90 + gapDegrees / 2 }  // gap centered at the bottom

    private var arc: some Shape { Circle().trim(from: 0, to: CGFloat(sweep / 360)) }
    private var markerRadians: Double { max(0, min(1, fraction)) * sweep * .pi / 180 }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2 - lineWidth / 2
            ZStack {
                ZStack {
                    arc.stroke(Color.gray.opacity(0.25),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    arc.stroke(AngularGradient(gradient: gradient, center: .center,
                                               startAngle: .degrees(0), endAngle: .degrees(sweep)),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    Circle()
                        .fill(.white)
                        .frame(width: lineWidth + 1.5, height: lineWidth + 1.5)
                        .overlay(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 0.5))
                        .offset(x: radius * CGFloat(cos(markerRadians)),
                                y: radius * CGFloat(sin(markerRadians)))
                }
                .rotationEffect(.degrees(startDegrees))
                center()
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

struct FeelsCircularView: View {
    let entry: FeelsEntry
    var body: some View {
        let g = FeelsGauge(entry)
        RangeGauge(gradient: g.gradient, fraction: g.fraction) { center(g) }
    }

    // The center disc (single, or split in-sun/in-shade) inset within the ring,
    // with the outlined temperature on top.
    @ViewBuilder
    private func center(_ g: FeelsGauge) -> some View {
        ZStack {
            Group {
                if let sun = g.centerSunColor, let shade = g.centerShadeColor {
                    VStack(spacing: 0) {
                        Rectangle().fill(sun)
                        Rectangle().fill(shade)
                    }
                    .clipShape(Circle())
                } else if let c = g.centerColor {
                    Circle().fill(c)
                }
            }
            .padding(7)

            if let fill = g.centerTextColor, let outline = g.centerOutlineColor {
                OutlinedText(text: g.tempLabel, fill: fill, outline: outline)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.4)
            } else {
                Text(g.tempLabel)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.4)
                    .foregroundStyle(.primary)
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
