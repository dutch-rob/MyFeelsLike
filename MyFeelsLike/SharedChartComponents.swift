// SPDX-License-Identifier: GPL-3.0-or-later
//
//  SharedChartComponents.swift
//  MyFeelsLike
//
//  Pieces shared by the forecast screens (HereTodayView, TenDayView) and the
//  Compare screen: the loading view, the chart legend row, the WeatherKit
//  attribution link, the compact clock-hour formatter, the GraphKey settings
//  keys, the MyFeelsLike cell-color helpers, and a small View convenience.
//

import SwiftUI
import UIKit

// MARK: - Long-press location (for the graph scrubber)

/// A transparent layer whose UIKit long-press reports the touch *location* (which
/// SwiftUI's LongPressGesture does not). It fails on movement, so a swipe passes
/// through, and it recognises simultaneously with other gestures. Used to drop
/// the scrubber line exactly under the finger.
struct LongPressLocator: UIViewRepresentable {
    var minimumDuration: Double = 0.35
    /// Report the location in the window (global) instead of the layer's bounds.
    var inWindow: Bool = false
    /// A plain tap on the chart, used to put the scrubber away. Lives here
    /// rather than as a SwiftUI .onTapGesture because this view sits on top of
    /// the chart and would otherwise swallow it.
    ///
    /// Declared before `onEvent` deliberately: the memberwise initialiser binds
    /// a trailing closure to its *last* parameter, so putting this one after
    /// `onEvent` would silently re-point every existing trailing-closure call
    /// site at the tap handler instead of the long-press one.
    var onTap: (() -> Void)? = nil
    var onEvent: (CGPoint, UIGestureRecognizer.State) -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        let lp = UILongPressGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.handle(_:)))
        lp.minimumPressDuration = minimumDuration
        lp.delegate = context.coordinator
        v.addGestureRecognizer(lp)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        v.addGestureRecognizer(tap)
        return v
    }
    func updateUIView(_ v: UIView, context: Context) {
        context.coordinator.onEvent = onEvent
        context.coordinator.inWindow = inWindow
        context.coordinator.onTap = onTap
    }
    func makeCoordinator() -> Coordinator { Coordinator(onEvent, inWindow, onTap) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onEvent: (CGPoint, UIGestureRecognizer.State) -> Void
        var inWindow: Bool
        var onTap: (() -> Void)?
        init(_ onEvent: @escaping (CGPoint, UIGestureRecognizer.State) -> Void, _ inWindow: Bool,
             _ onTap: (() -> Void)? = nil) {
            self.onEvent = onEvent; self.inWindow = inWindow; self.onTap = onTap
        }
        @objc func handle(_ g: UILongPressGestureRecognizer) {
            onEvent(g.location(in: inWindow ? nil : g.view), g.state)
        }
        @objc func handleTap(_ g: UITapGestureRecognizer) { onTap?() }
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

// MARK: - Shared components

struct ForecastLoadingView: View {
    var progress: LoadProgress
    var nowTick: Date
    var errorMessage: String?

    /// What the app is actually waiting for right now, so the screen says
    /// "Waiting for location update" rather than a generic "Loading…".
    private var headline: String {
        func running(_ s: LoadStep) -> Bool {
            if case .inProgress = (progress.steps[s] ?? .pending) { return true }
            return false
        }
        if running(.location) { return "Waiting for location update…" }
        if running(.weather)  { return "Waiting for latest weather data…" }
        if running(.geocode)  { return "Looking up the name of this place…" }
        // Nothing in flight: either just starting, or everything finished and
        // we're waiting on the data to arrive.
        return progress.steps.isEmpty ? "Starting…" : "Loading forecast…"
    }

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(headline)
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(LoadStep.allCases) { step in
                    HStack(spacing: 8) {
                        stepIcon(for: step)
                        Text(step.rawValue)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if case .inProgress(let t) = (progress.steps[step] ?? .pending),
                           nowTick.timeIntervalSince(t) > 2 {
                            Text("(working…)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func stepIcon(for step: LoadStep) -> some View {
        switch progress.steps[step] ?? .pending {
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .inProgress(let t):
            if nowTick.timeIntervalSince(t) > 2 {
                ProgressView().frame(width: 14, height: 14)
            } else {
                Image(systemName: "hourglass").foregroundStyle(.secondary)
            }
        case .failure:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .pending:
            Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
        }
    }
}

struct ChartLegendRow: View {
    let entries: [(color: Color, label: String, isArea: Bool)]
    /// Dash pattern per entry, parallel to `entries`. In "No color" mode the
    /// swatches are all the same gray, so the pattern is the only thing that
    /// says which curve is which — the legend has to show it.
    var dashes: [[CGFloat]] = []
    /// Text color — follows the sky (black by day, white by night) so labels
    /// stay legible on the weather background.
    var ink: Color = .secondary

    var body: some View {
        // One line when the panel is wide enough; two lines in narrow panels
        // (e.g. three-across iPhone landscape) instead of wrapping mid-word.
        ViewThatFits(in: .horizontal) {
            row(entries)
            VStack(alignment: .leading, spacing: 2) {
                row(Array(entries.prefix((entries.count + 1) / 2)))
                row(Array(entries.suffix(entries.count / 2)))
            }
        }
    }

    private func dash(for label: String) -> [CGFloat]? {
        guard let i = entries.firstIndex(where: { $0.label == label }), i < dashes.count else { return nil }
        return dashes[i]
    }

    @ViewBuilder
    private func row(_ items: [(color: Color, label: String, isArea: Bool)]) -> some View {
        HStack(spacing: 14) {
            ForEach(items, id: \.label) { e in
                HStack(spacing: 4) {
                    if e.isArea {
                        // Full strength: the charts draw their bands at full
                        // opacity, so dimming the swatch made a vivid palette
                        // look muted in the legend.
                        RoundedRectangle(cornerRadius: 2)
                            .fill(e.color)
                            .frame(width: 18, height: 8)
                    } else if let dash = dash(for: e.label), !dash.isEmpty {
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: 1))
                            p.addLine(to: CGPoint(x: 18, y: 1))
                        }
                        .stroke(e.color, style: StrokeStyle(lineWidth: 2, dash: dash))
                        .frame(width: 18, height: 2)
                    } else {
                        Rectangle()
                            .fill(e.color)
                            .frame(width: 18, height: 2)
                    }
                    Text(e.label)
                        .font(.caption2)
                        .foregroundStyle(ink)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct WeatherAttributionLink: View {
    let info: WeatherAttributionInfo
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Link(destination: info.legalPageURL) {
            AsyncImage(
                url: colorScheme == .dark ? info.darkLogoURL : info.lightLogoURL
            ) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text("Apple Weather").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(height: 12)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Scrubber readout formatting

/// Shared number formatting for the long-press readout. Kept narrow on purpose:
/// the card sits on the graph, and at a larger font a wide card was covering the
/// scrub line for hours near the middle of the x-axis. Paired values use a slash
/// rather than parentheses (matching the "Temp/feels" label), and cloud's
/// by-altitude breakdown moves to its own row.
enum ScrubFormat {
    /// "53.2/48.5" — one decimal each, no brackets or spaces.
    static func pair(_ a: Double, _ b: Double) -> String {
        String(format: "%.1f/%.1f", a, b)
    }
    /// "11/72/41" — low/medium/high cloud, percent, no labels.
    static func cloudParts(_ p: ForecastPoint) -> String {
        String(format: "%.0f/%.0f/%.0f",
               p.cloudCoverLow * 100, p.cloudCoverMedium * 100, p.cloudCoverHigh * 100)
    }
}

// MARK: - Clock format

/// Compact hour-of-day label. 24-hour → "00"…"23". 12-hour → 1…12 with the
/// noon tick spelled out ("noon") and midnight shown as "12", no am/pm suffix.
func clockHourLabel(_ hour: Int, use12: Bool) -> String {
    let h = ((hour % 24) + 24) % 24
    guard use12 else { return String(format: "%02d", h) }
    if h == 12 { return "noon" }
    let hr = h % 12
    return hr == 0 ? "12" : "\(hr)"
}

// MARK: - Graph visibility settings (user-toggleable in Settings)

/// Whether the weather-sky background is actually drawn behind this view.
/// The `graphSky` setting only records that the user wants it — the table
/// screen hides it regardless, and in the iPad's side-by-side layout the graph
/// panes then sit on a plain light background, where sky-white ink is
/// invisible. Views that pick ink for legibility must read this, not the
/// setting.
private struct SkyIsVisibleKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    var skyIsVisible: Bool {
        get { self[SkyIsVisibleKey.self] }
        set { self[SkyIsVisibleKey.self] = newValue }
    }
}

/// @AppStorage keys for which graph series the user wants to see. All default
/// to true. Shared by the forecast views, ContentView (tab gating) and Settings.
enum GraphKey {
    static let temp     = "graphTemp"
    static let wetBulb  = "graphWetBulb"
    static let dewPoint = "graphDewPoint"
    static let feels    = "graphFeels"
    static let color   = "graphColor"
    static let precip   = "graphPrecip"
    static let wind     = "graphWind"
    static let gust     = "graphGust"
    static let sky      = "graphSky"

    /// True when at least one graph series is enabled (any forecast panel would
    /// show). When false, the 24h/10-day screens are hidden entirely.
    static func anyGraphEnabled(_ d: UserDefaults = .standard) -> Bool {
        let all = [temp, wetBulb, dewPoint, feels, color, precip, wind, gust]
        // Missing key defaults to true (on).
        return all.contains { d.object(forKey: $0) == nil || d.bool(forKey: $0) }
    }
}

// MARK: - Personalized color background for the temperature chart

/// Cell color for the MyFeelsLike panels (24h strip + 10-day heatmap): the
/// score's color at full opacity. Reliability is conveyed by the cell's
/// width (see myFeelsLikeReliability), not by fading. Gray when no score.
func myFeelsLikeHeatColor(_ p: ForecastPoint) -> Color {
    ColorScale.feelsColor(score: p.myFeelsLikeScore, opacity: 1)
}

/// Prediction reliability in 0…1, used to scale a cell's width so uncertain
/// forecasts read as a thinner band rather than a fainter color. A small
/// floor keeps even the least reliable cell visible as a sliver.
func myFeelsLikeReliability(_ p: ForecastPoint) -> Double { p.myFeelsLikeWidth }

/// How the in-shade vs in-sun difference is drawn in the color band / heatmap.
/// `separate` (the default) shows two distinct bars/heatmaps — clearest at a
/// glance; `gradient` blends shade→sun within each cell — more compact and
/// preferred by some once they know the code.
/// Dash patterns that tell the weather curves apart without relying on color,
/// for "No color" mode. Order matters only in that neighbouring series should
/// not share a pattern; the names say what each looks like.
enum SeriesDash {
    static let solid:   [CGFloat] = []
    static let dashed:  [CGFloat] = [7, 4]
    static let dotted:  [CGFloat] = [1.5, 3.5]
    static let dashDot: [CGFloat] = [8, 3, 1.5, 3]

    /// The stroke for one series: plain when color already separates them,
    /// patterned when it does not.
    static func stroke(_ pattern: [CGFloat], patterned: Bool) -> StrokeStyle {
        StrokeStyle(lineWidth: seriesLineWidth, dash: patterned ? pattern : [])
    }
}

/// Stroke width for the weather series curves (temperature, wet bulb, dew
/// point, wind, precipitation). Wider than a hairline so the curves hold their
/// own against the painted sky behind them — a 1-point line vanished into the
/// night background. Scrub rules and grid lines keep their own thinner widths.
let seriesLineWidth: CGFloat = 2.2

/// Saturation applied to the weather series (temperature bands/lines and the
/// precip/wind panel). `vivid` is full-strength; `muted` softens them for
/// people who find the default colors too harsh. The MyFeelsLike score colors
/// are deliberately left untouched — they carry meaning.
enum GraphPalette: String, CaseIterable {
    case vivid
    case muted

    /// Multiplier for SwiftUI's `.saturation(_:)` on the series panels.
    var saturation: Double { self == .muted ? 0.55 : 1.0 }
}

/// How the temperature and precip/wind curves are drawn.
/// `area` (default) fills each series from the baseline — bold, easy to read at
/// a glance. `lines` draws thin curves with no fill — less visual weight, closer
/// to a classic meteogram, and (unlike the filled precip/wind panel) reads
/// bottom-up rather than hanging from the top.
enum ChartSeriesStyle: String, CaseIterable {
    case area
    case lines
}

// MARK: - View extension

extension View {
    @ViewBuilder
    func ifLet<T, Content: View>(_ value: T?, transform: (Self, T) -> Content) -> some View {
        if let v = value { transform(self, v) } else { self }
    }
}

/// The point in `series` closest in time to `date`.
func nearestForecastPoint(to date: Date, in series: [ForecastPoint]) -> ForecastPoint? {
    series.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
}

// MARK: - Day axis labels

private let weekdayFmt: DateFormatter = {
    let f = DateFormatter(); f.locale = .current; f.dateFormat = "EEE"; return f
}()

/// Label for a day tick on a scrolled/zoomed axis.
///
/// Once the window covers many days there isn't room for "Mo 15" on every tick —
/// two-digit days of the month are the tight case — so the caller works out how
/// much width each tick gets and we drop the weekday when it won't fit.
func dayTickLabel(_ date: Date, includeWeekday: Bool) -> String {
    let day = Calendar.current.component(.day, from: date)
    guard includeWeekday else { return "\(day)" }
    let wd = String(weekdayFmt.string(from: date).prefix(2))
    return "\(wd) \(day)"
}

/// Whether a day axis has room for the weekday as well as the day number.
/// `plotWidth` is the chart's width; `days` the number of day ticks across it.
///
/// Two-digit days of the month are the binding case, needing about 44 pt. One
/// threshold is applied to every window rather than switching style as the
/// month rolls over, which would make labels flicker between forms while
/// scrolling.
func dayAxisFitsWeekday(plotWidth: CGFloat, days: Double) -> Bool {
    guard days > 0 else { return true }
    return (plotWidth - 56) / days >= 44
}

// MARK: - "Now" marker

/// Marker for the current time: a ring in the series colour whose centre is cut
/// out of the page, so it reads as hollow in both light and dark appearance. A
/// solid dot of the series colour disappeared into the filled band beneath it.
struct NowMarkerSymbol: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle().fill(Color(.systemBackground))
            Circle().strokeBorder(color, lineWidth: 2.5)
        }
        .frame(width: 13, height: 13)
    }
}
