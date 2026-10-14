// SPDX-License-Identifier: GPL-3.0-or-later
//
//  FoldTimelineView.swift
//  MyFeelsLike
//
//  Optional "integrated fold" view (Settings → Timeline fold). Instead of
//  paging between a 24-hour screen and a 10-day screen, one continuous timeline
//  morphs between them: a zoom level 0…1 drives the morph, and
//  everything animates together —
//    • the temperature and precip/wind charts zoom their x-axis from a single
//      day out to the whole forecast, and
//    • the MyFeelsLike color panel folds from a flat 24-hour band into the
//      10-day time-of-day heat map (each day's 24 hourly cells swing from
//      horizontal to vertical, drawn as one rotated+scaled band per day so it
//      stays a rigid ruler through the swing).
//
//  Built on real forecast/model data. It reuses the same inputs the paged
//  screens get and leaves them untouched.
//

import SwiftUI
import Charts

struct FoldTimelineView: View {
    var series: [ForecastPoint]          // 10-day, personalized
    var historic: [ForecastPoint] = []
    var current: ForecastPoint? = nil
    var progressLoad: LoadProgress = LoadProgress()
    var nowTick: Date = .now
    var sunrise: Date? = nil
    var sunset: Date? = nil
    var errorMessage: String? = nil
    var attribution: WeatherAttributionInfo? = nil
    var onRefresh: (() async -> Void)? = nil
    /// Left edge of the visible window, as an offset from "now". Shared with
    /// ContentView so the graph and the table stay on the same moment.
    @Binding var startOffset: TimeInterval
    /// Vertical swipe asks for the table screen (wired up only when the table is
    /// enabled in Settings). Pinch owns zooming now, which frees this up.
    var onShowTable: (() -> Void)? = nil
    var activeFeatures: Set<Feature> = []

    @AppStorage(SettingsKey.useFahrenheit) private var useFahrenheit = true
    @AppStorage(SettingsKey.use12HourClock) private var use12Hour = false
    @AppStorage(GraphKey.temp)     private var graphTemp     = true
    @AppStorage(GraphKey.wetBulb)  private var graphWetBulb  = false
    @AppStorage(GraphKey.dewPoint) private var graphDewPoint = false
    @AppStorage(GraphKey.feels)    private var graphFeels    = true
    @AppStorage(GraphKey.color)    private var graphColor    = true
    @AppStorage(GraphKey.precip)   private var graphPrecip   = true
    @AppStorage(GraphKey.wind)     private var graphWind     = true
    @AppStorage(GraphKey.gust)     private var graphGust     = true
    @AppStorage(GraphKey.sky)      private var graphSky      = true
    @AppStorage(SettingsKey.chartSeriesStyle) private var chartStyle = ChartSeriesStyle.lines
    @AppStorage(SettingsKey.graphPalette) private var graphPalette = GraphPalette.vivid
    @AppStorage(SettingsKey.colorVisionMode)
    private var visionMode = ColorScale.ColorVisionMode.full
    @AppStorage(SettingsKey.noColorStyle)
    private var noColorStyle = ColorScale.NoColorStyle.lineGraph

    /// 0 = 24-hour view, 1 = 10-day view. Scrubbed by a horizontal swipe.
    /// Zoom level: 0 = a 24-hour window, 1 = the whole −10d…+10d series. Not
    /// snapped, so any intermediate zoom is a valid resting place. Also drives
    /// the fold: the band rotates into the heat map as this rises.
    @State private var zoom: Double = 0
    @State private var panBase: TimeInterval? = nil
    @State private var zoomBase: Double? = nil
    /// Time held fixed at the centre while zooming.
    @State private var zoomAnchor: Date? = nil
    @State private var dragAxis: DragAxis? = nil
    private enum DragAxis { case horizontal, vertical }
    /// Plot width, kept so the day axis can decide whether the weekday fits.
    @State private var plotWidth: CGFloat = 0
    /// Progress captured at the start of the current swipe (nil when not dragging).
    /// The time the user is reading via long-press scrub (nil = not scrubbing).
    /// While set, the transition swipe is suspended and a readout is shown.
    @State private var scrubDate: Date? = nil
    /// The plots' on-screen (global) x-range, so a long press in the gaps between
    /// panels can be mapped to a time too.
    @State private var plotXRange: ClosedRange<CGFloat>? = nil

    /// Stacked translucent areas become indistinguishable grays once hue
    /// carries nothing, so No color mode always draws curves.
    private var linesOnly: Bool { chartStyle == .lines || visionMode == .noColor }
    private var patternedSeries: Bool { visionMode == .noColor }
    private var comfortAsLineGraph: Bool {
        visionMode == .noColor && noColorStyle == .lineGraph
    }
    /// The model learned a sun effect, so the band has two things to show.
    private var sunFeatureActive: Bool { activeFeatures.contains(.sun) }
    private var tempVisible: Bool { graphTemp || graphWetBulb || graphDewPoint || graphFeels }
    private var windVisible: Bool { graphPrecip || graphWind || graphGust }

    // MARK: Data

    private var allPoints: [ForecastPoint] {
        (historic + (current.map { [$0] } ?? []) + series).sorted { $0.date < $1.date }
    }

    /// One calendar day of hourly scores (nil where no point/no model), with the
    /// reliability width for each hour so the fold can narrow uncertain hours
    /// exactly like the paged screens do.
    private struct DayCol {
        let start: Date
        let scores: [Double?]
        let widths: [Double]
        /// In-sun scores, when the model learned a sun effect. Empty otherwise.
        let sunScores: [Double?]
    }

    private var dayCols: [DayCol] {
        let cal = Calendar.current
        var byDay: [Date: [Int: (Double, Double, Double?)]] = [:]
        for p in allPoints {
            guard let s = p.myFeelsLikeScore else { continue }
            let d = cal.startOfDay(for: p.date)
            let h = cal.component(.hour, from: p.date)
            // Shade is the band's main value; sun rides alongside it. No
            // daylight test here: after dark the prediction already collapses
            // sun onto shade, so the two halves simply read the same.
            let shade = p.myFeelsLikeShadeScore ?? s
            byDay[d, default: [:]][h] = (shade, myFeelsLikeReliability(p), p.myFeelsLikeSunScore)
        }
        return byDay.keys.sorted().map { d in
            let row = byDay[d]
            return DayCol(start: d,
                          scores: (0..<24).map { row?[$0]?.0 },
                          widths: (0..<24).map { row?[$0]?.1 ?? 1 },
                          sunScores: (0..<24).map { row?[$0]?.2 })
        }
    }

    private var hasModel: Bool { allPoints.contains { $0.myFeelsLikeScore != nil } }

    // MARK: Time domain (interpolated by progress)

    /// Narrow (24-hour) window: a rolling day starting at "now", so it's always
    /// full — matching the 24-hour screen rather than the calendar day (whose
    /// morning is in the past and has no forecast).
    private var dataLo: Date { allPoints.first?.date ?? nowTick }
    private var dataHi: Date { series.last?.date ?? nowTick.addingTimeInterval(24 * 3600) }
    /// Widest window: ten days, or less if that is all the data we have.
    private var fullSpan: TimeInterval {
        min(240 * 3600, max(24 * 3600, dataHi.timeIntervalSince(dataLo)))
    }
    private static let minSpan: TimeInterval = 24 * 3600
    /// Visible span, interpolated by the zoom level.
    private var span: TimeInterval { Self.minSpan + (fullSpan - Self.minSpan) * zoom }

    private func clampStart(_ o: TimeInterval) -> TimeInterval {
        TimelineScroll.clampStartOffset(o, span: span, now: nowTick,
                                        dataLo: dataLo, dataHi: dataHi)
    }

    /// Where the fold changes character. Below this the zoom only widens the
    /// window (the color band just gets thinner as each hour claims less
    /// width); above it the band rotates into the heat map. The window's extent
    /// is no longer tied to this — the pinch sets that — but the morph still is.
    private let foldSplit = 0.4

    /// 0…1 through the widening stage.
    private var zoomPhase: Double { min(1, zoom / foldSplit) }
    /// 0…1 through the rotating stage (0 until the widening stage is done).
    private var rotatePhase: Double { max(0, (zoom - foldSplit) / (1 - foldSplit)) }

    /// The window now scrolls freely rather than growing out of "now": its
    /// width comes from the zoom level and its position from `startOffset`.
    private var visLo: Date { nowTick.addingTimeInterval(clampStart(startOffset)) }
    private var visHi: Date { visLo.addingTimeInterval(span) }
    private var visDomain: ClosedRange<Date> {
        // Small proportional lead-in so the "now" rings are not clipped at the
        // left edge; see HereTodayView.visibleRange.
        let sliver = span * 0.03
        var lo = visLo.addingTimeInterval(-sliver)
        // That sliver alone is not always enough. The current observation is
        // timestamped on the hour, so it can sit up to an hour behind "now" —
        // and with the window starting at "now", its rings then land on or
        // outside the edge and get sliced in half. Give way to the marker, but
        // only when it is close enough to the edge to be the one being clipped:
        // scrolled elsewhere, the window must not stretch back to it.
        if let n = nowPoint,
           n.date < lo.addingTimeInterval(sliver),
           n.date > lo.addingTimeInterval(-3 * sliver) {
            lo = n.date.addingTimeInterval(-sliver)
        }
        return lo...max(lo.addingTimeInterval(3600), visHi)
    }

    /// Points inside the visible window. The y-ranges come from these rather
    /// than the whole ±10 days: scaling to data that is off-screen left the
    /// charts using only part of their height.
    private var visibleSeries: [ForecastPoint] {
        let lo = visLo.addingTimeInterval(-2 * 3600)
        let hi = visHi.addingTimeInterval(2 * 3600)
        let inWindow = allPoints.filter { $0.date >= lo && $0.date <= hi }
        return inWindow.isEmpty ? allPoints : inWindow
    }

    // MARK: Y ranges (over all data, stable while zooming)

    private var tempYDomain: ClosedRange<Double> {
        var v: [Double] = []
        for p in visibleSeries {
            if graphTemp     { v.append(useFahrenheit ? p.temperatureF : p.temperatureC) }
            if graphWetBulb  { v.append(useFahrenheit ? p.wetBulbF : p.wetBulbC) }
            if graphDewPoint { v.append(useFahrenheit ? p.dewPointF : p.dewPointC) }
            if graphFeels    { v.append(useFahrenheit ? p.apparentTemperatureF : p.apparentTemperatureC) }
        }
        guard let lo = v.min(), let hi = v.max() else { return 0...1 }
        let pad = max(1, (hi - lo) * 0.08)
        return (lo - pad)...(hi + pad)
    }
    private var windYMax: Double {
        var v: [Double] = []
        for p in visibleSeries {
            if graphPrecip { v.append(p.precipProbability * 100) }
            if graphGust   { v.append(useFahrenheit ? p.windGustMPH : p.windGustKPH) }
            if graphWind   { v.append(useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH) }
        }
        let hi = v.max() ?? 1
        return hi + max(1, hi * 0.08)
    }

    /// Taken from whoever drew the sky; see SkyIsDayKey.
    @Environment(\.skyIsDay) private var skyIsDay
    @Environment(\.skyIsVisible) private var skyIsVisible
    /// The sky is only behind us when the user wants it *and* the screen we
    /// are on actually draws it (the table screen does not).
    private var overSky: Bool { graphSky && skyIsVisible }
    private var axisInk: Color { overSky ? (skyIsDay ? .black : .white) : .primary }
    /// Weather-series colors sit on a near-black sky at night, where they read
    /// dimmer than the same colors do on the pale daytime sky. A small lift
    /// restores the contrast. Only when the sky is actually behind them.
    private var seriesBrightness: Double { overSky && !skyIsDay ? 0.14 : 0 }

    // MARK: Scrubbing (long-press to read exact values; coexists with the swipe)

    private var scrubPoint: ForecastPoint? {
        guard let t = scrubDate else { return nil }
        return allPoints.min { abs($0.date.timeIntervalSince(t)) < abs($1.date.timeIntervalSince(t)) }
    }


    /// Snap a plot-relative x (via a chart proxy) to the nearest forecast hour.
    private func snapDate(atX x: CGFloat, proxy: ChartProxy) -> Date? {
        guard let d = proxy.value(atX: x, as: Date.self) else { return nil }
        return allPoints.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) }?.date
    }

    /// Always present: a UIKit long-press drops the scrub line exactly where the
    /// finger is (and moves it if you keep holding and dragging). Also records the
    /// plot's global x-range so presses in the gaps between panels can map too.
    @ViewBuilder
    private func scrubEntry(_ proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            let plot = proxy.plotFrame.map { geo[$0] }
            LongPressLocator { loc, state in
                guard let plot else { return }
                let x = loc.x - plot.origin.x
                if (state == .began || state == .changed), let d = snapDate(atX: x, proxy: proxy) {
                    scrubDate = d
                }
            }
            .onAppear { recordPlotX(plot, geo: geo) }
            .onChange(of: geo.frame(in: .global)) { _, _ in recordPlotX(plot, geo: geo) }
        }
    }

    private func recordPlotX(_ plot: CGRect?, geo: GeometryProxy) {
        guard let plot else { return }
        let originX = geo.frame(in: .global).minX
        plotXRange = (originX + plot.minX)...(originX + plot.minX + plot.width)
    }

    /// Nearest forecast hour for a global (window) x — used by the long press in
    /// the gaps between panels.
    private func snapDate(globalX x: CGFloat) -> Date? {
        guard let r = plotXRange, r.upperBound > r.lowerBound else { return nil }
        let frac = min(1, max(0, (x - r.lowerBound) / (r.upperBound - r.lowerBound)))
        let lo = visLo.timeIntervalSinceReferenceDate, hi = visHi.timeIntervalSinceReferenceDate
        let t = Date(timeIntervalSinceReferenceDate: lo + Double(frac) * (hi - lo))
        return allPoints.min { abs($0.date.timeIntervalSince(t)) < abs($1.date.timeIntervalSince(t)) }?.date
    }

    /// A background layer over the whole view so a long press *between* panels
    /// (or on a label/legend) also starts the scrubber.
    private var scrubGapEntry: some View {
        LongPressLocator(inWindow: true) { loc, state in
            if (state == .began || state == .changed), let d = snapDate(globalX: loc.x) {
                scrubDate = d
            }
        }
    }

    /// Active only while scrubbing: a drag moves the line; a tap (no movement)
    /// dismisses it without first nudging the line.
    @ViewBuilder
    private func scrubDragLayer(_ proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle().fill(Color.clear).contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            // Ignore the tiny jitter of a tap so it doesn't move
                            // the line before it dismisses.
                            guard abs(v.translation.width) > 4 || abs(v.translation.height) > 4 else { return }
                            guard let pf = proxy.plotFrame else { return }
                            if let d = snapDate(atX: v.location.x - geo[pf].origin.x, proxy: proxy) {
                                scrubDate = d
                            }
                        }
                        .onEnded { v in
                            if abs(v.translation.width) < 5 && abs(v.translation.height) < 5 {
                                scrubDate = nil     // tap to finish scrubbing
                            }
                        }
                )
        }
    }

    @ChartContentBuilder
    private func scrubRule() -> some ChartContent {
        if let t = scrubDate {
            RuleMark(x: .value("scrub", t))
                .foregroundStyle(axisInk.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    /// 0 = line at far left, 1 = far right (drives which side the readout sits on).
    private var scrubFraction: Double {
        guard let t = scrubDate else { return 0.5 }
        let lo = visLo.timeIntervalSinceReferenceDate, hi = visHi.timeIntervalSinceReferenceDate
        guard hi > lo else { return 0.5 }
        return min(1, max(0, (t.timeIntervalSinceReferenceDate - lo) / (hi - lo)))
    }

    /// Values that belong to the temperature panel (shown over it).
    private func scrubReadoutTop(_ p: ForecastPoint) -> some View {
        let unit = useFahrenheit ? "°F" : "°C"
        return readoutCard {
            HStack(spacing: 6) {
                Text(scrubTimeLabel(p.date)).font(.subheadline.weight(.semibold))
                Image(systemName: p.symbolName).font(.subheadline)
                if let s = p.myFeelsLikeScore {
                    let c = max(ColorScale.minScore, min(ColorScale.maxScore, s))
                    Text(String(format: "%.0f", c))
                        .font(.subheadline.weight(.bold)).monospacedDigit()
                        .foregroundStyle(ColorScale.contrastingText(forScore: c))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(ColorScale.color(forScore: c), in: RoundedRectangle(cornerRadius: 3))
                }
                Spacer(minLength: 10)
                Button { scrubDate = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.callout).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            readoutRow("Temp/feels \(unit)", ScrubFormat.pair(
                useFahrenheit ? p.temperatureF : p.temperatureC,
                useFahrenheit ? p.apparentTemperatureF : p.apparentTemperatureC), .green)
            readoutRow("Wet bulb \(unit)", String(format: "%.1f", useFahrenheit ? p.wetBulbF : p.wetBulbC), .blue)
            readoutRow("Dew pt \(unit)", String(format: "%.1f", useFahrenheit ? p.dewPointF : p.dewPointC), .red)
            readoutRow("UV", String(format: "%.0f", p.uvIndex), .orange)
            readoutRow("Cloud %", String(format: "%.0f", p.cloudCover * 100), .secondary)
            readoutRow("  low/mid/high", ScrubFormat.cloudParts(p), .secondary)
        }
    }

    /// Values that belong to the precip/wind panel (shown over it).
    private func scrubReadoutBottom(_ p: ForecastPoint) -> some View {
        let windUnit = useFahrenheit ? "mph" : "kph"
        return readoutCard {
            readoutRow("Wind \(windUnit)",
                       String(format: "%.0f", useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH), .red)
            readoutRow("Gust \(windUnit)",
                       String(format: "%.0f", useFahrenheit ? p.windGustMPH : p.windGustKPH), .red)
            readoutRow("Precip mm", String(format: "%.1f", p.precipitationMM), .blue)
            readoutRow("Precip %", String(format: "%.0f", p.precipProbability * 100), .blue)
        }
    }

    private func readoutCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 1) { content() }
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            .fixedSize()
    }

    private func readoutRow(_ label: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value).font(.footnote.weight(.medium)).monospacedDigit()
                .foregroundStyle(tint.mix(with: .primary, by: 0.25))
        }
    }

    private func scrubTimeLabel(_ d: Date) -> String {
        let cal = Calendar.current
        let h = cal.component(.hour, from: d)
        let hh: String
        if use12Hour {
            if h == 0 { hh = "12 am" } else if h == 12 { hh = "noon" } else { hh = h < 12 ? "\(h) am" : "\(h - 12) pm" }
        } else { hh = String(format: "%02d:00", h) }
        // Include the weekday once we're zoomed past a day or so.
        if visHi.timeIntervalSince(visLo) > 2 * 86400 {
            let f = DateFormatter(); f.locale = .current; f.dateFormat = "EEE"
            return "\(f.string(from: d)) \(hh)"
        }
        return hh
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            if allPoints.isEmpty {
                ForecastLoadingView(progress: progressLoad, nowTick: nowTick, errorMessage: errorMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // The color band is thin at 24-hour and grows to the full heat map
                // at 10-day; the space it frees goes to the two graphs. Reserve a
                // little at the bottom so the legend clears the floating toolbar.
                let overhead: CGFloat = 40 + 58     // scenario strip + indicator, + toolbar
                let avail = max(220, h - overhead)
                // The band only needs its full height once it starts standing
                // up, so it keeps the graphs' space through the widening stage.
                // The rotating band grows as it tips upright; a line graph does
                // not rotate, so it takes one steady share big enough to carry
                // six named ticks without crushing them.
                //
                // The two ends match the paged screens: the taller 24-hour band
                // and the shorter 10-day heatmap. The change between them is
                // spent in the first 40% of the rotation rather than spread
                // across all of it, so the strips settle to their final
                // thickness early and the later, most-overlapping part of the
                // turn happens at a steady size.
                let heightPhase = smoothstep(min(1, rotatePhase / 0.4))
                let colorH = comfortAsLineGraph
                    ? avail * 0.26
                    : lerp(avail * 0.15, avail * 0.238, heightPhase)
                let graphsH = avail - colorH
                // A ScrollView sized to exactly one screen: it never actually
                // scrolls, but it restores pull-to-refresh (.refreshable only
                // works inside a scroll view) without disturbing the horizontal
                // morph swipe.
                ScrollView {
                    VStack(spacing: 8) {
                        ScenarioStrip(activeFeatures: activeFeatures)
                        modeIndicator
                        if tempVisible { temperatureChart(height: graphsH * 0.56) }
                        if graphColor { colorPanel(height: colorH) }
                        if windVisible { precipWindChart(height: graphsH * 0.44) }
                        if let attribution { WeatherAttributionLink(info: attribution) }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 52)
                    .frame(minHeight: h - 4)
                    .contentShape(Rectangle())
                    // Behind everything: catches a long press in the gaps between
                    // panels. Presses on a panel are caught by its own scrubEntry in
                    // front. The swipe drives the 24h↔10-day morph.
                    .background(scrubGapEntry)
                    .gesture(scrubGesture(width: geo.size.width)
                                .simultaneously(with: zoomGesture()))
                }
                .onAppear { plotWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, w in plotWidth = w }
            }
        }
    }

    /// Thin swipe hint (replaces the segmented control to give the graphs room).
    /// Since the swipe can now rest anywhere, an end label is only emphasised
    /// when the view is actually at that end; in between, both are dimmed and a
    /// span readout says how much of the forecast is on screen.
    /// How wide the window is and where it starts. The zoom has no discrete
    /// modes any more, so a label beats a two-ended indicator.
    private var modeIndicator: some View {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEEd MMM")
        return HStack(spacing: 6) {
            Image(systemName: "arrow.left.and.right")
                .font(.caption2).foregroundStyle(axisInk.opacity(0.5))
            Text(spanLabel).fontWeight(.semibold).monospacedDigit()
            Text("from \(f.string(from: visLo))").foregroundStyle(axisInk.opacity(0.6))
        }
        .font(.subheadline)
        .foregroundStyle(axisInk)
        .frame(maxWidth: .infinity)
    }

    /// How much time the visible window covers, for intermediate zoom levels.
    private var spanLabel: String {
        let hours = visHi.timeIntervalSince(visLo) / 3600
        if hours < 48 { return "\(Int(hours.rounded())) h" }
        return "\(Int((hours / 24).rounded())) days"
    }

    /// Horizontal drag pans through time; a vertical drag asks for the table.
    /// Zooming is a pinch now, which is the gesture people expect — and it frees
    /// the horizontal swipe to do what it does on every other screen.
    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { v in
                guard scrubDate == nil else { return }   // scrubbing wins
                if dragAxis == nil {
                    dragAxis = abs(v.translation.width) >= abs(v.translation.height)
                        ? .horizontal : .vertical
                }
                guard dragAxis == .horizontal else { return }
                if panBase == nil { panBase = startOffset }
                let dt = -Double(v.translation.width) / Double(max(1, width)) * span
                startOffset = clampStart((panBase ?? startOffset) + dt)
            }
            .onEnded { v in
                defer { dragAxis = nil; panBase = nil }
                guard scrubDate == nil else { return }
                if dragAxis == .vertical, abs(v.translation.height) > 40 {
                    onShowTable?()
                }
            }
    }

    /// Pinch to zoom, anchored on the middle of the window so the view does not
    /// slide sideways while zooming. Nothing snaps: any span is a resting place.
    private func zoomGesture() -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { v in
                if zoomBase == nil {
                    zoomBase = zoom
                    zoomAnchor = visLo.addingTimeInterval(span / 2)
                }
                let range = max(1, fullSpan - Self.minSpan)
                let baseSpan = Self.minSpan + range * (zoomBase ?? zoom)
                // Pinch out (magnification > 1) shows less time = zoom in.
                let wanted = baseSpan / max(0.05, v.magnification)
                let clamped = min(fullSpan, max(Self.minSpan, wanted))
                zoom = (clamped - Self.minSpan) / range
                if let c = zoomAnchor {
                    startOffset = clampStart(c.addingTimeInterval(-span / 2)
                                                .timeIntervalSince(nowTick))
                }
            }
            .onEnded { _ in zoomBase = nil; zoomAnchor = nil }
    }

    // MARK: Temperature

    /// Ink for a weather curve. In No color mode every curve is drawn in the
    /// same ink and told apart by its dash pattern, so hue carries nothing at
    /// all -- previously they were desaturated to *different* grays, which is
    /// still a lightness code. Follows the sky like the axes do: literal black
    /// would be invisible against the night background.
    private func seriesInk(_ base: Color) -> Color {
        patternedSeries ? axisInk : base
    }

    /// Point the "now" markers sit on: the current observation when there is
    /// one, else the nearest hour, and nothing at all if that is over an hour
    /// away. The window scrolls, so unlike the paged screens "now" is often not
    /// on screen — the x-scale clips the markers when it is not.
    private var nowPoint: ForecastPoint? {
        if let c = current { return c }
        guard let p = allPoints.min(by: {
            abs($0.date.timeIntervalSince(nowTick)) < abs($1.date.timeIntervalSince(nowTick))
        }) else { return nil }
        return abs(p.date.timeIntervalSince(nowTick)) <= 3600 ? p : nil
    }

    @ViewBuilder
    private func temperatureChart(height: CGFloat) -> some View {
        let dom = tempYDomain
        let base = dom.lowerBound
        VStack(alignment: .leading, spacing: 2) {
            ChartLegendRow(entries: tempLegend, dashes: tempLegendDashes, ink: axisInk)
                .saturation(visionMode == .noColor ? 0 : graphPalette.saturation).padding(.leading, gutter)
            Chart {
                ForEach(allPoints) { p in
                    let dry = useFahrenheit ? p.temperatureF : p.temperatureC
                    let wet = useFahrenheit ? p.wetBulbF : p.wetBulbC
                    let dew = useFahrenheit ? p.dewPointF : p.dewPointC
                    let app = useFahrenheit ? p.apparentTemperatureF : p.apparentTemperatureC
                    if graphTemp     { tempMark(p.date, dry, .green, base: base, key: "dry",
                                                 dash: SeriesDash.dashed) }
                    if graphWetBulb  { tempMark(p.date, wet, .blue,  base: base, key: "wet",
                                                 dash: SeriesDash.dotted) }
                    if graphDewPoint { tempMark(p.date, dew, .red,   base: base, key: "dew",
                                                 dash: SeriesDash.dashDot) }
                    if graphFeels {
                        LineMark(x: .value("t", p.date), y: .value("app", app), series: .value("s", "app"))
                            .foregroundStyle(seriesInk(.purple))
                            .lineStyle(SeriesDash.stroke(SeriesDash.solid, patterned: patternedSeries))
                            .interpolationMethod(.linear)
                    }
                }
                // Hollow rings at the current hour, matching the paged screens.
                if let n = nowPoint {
                    if graphTemp {
                        PointMark(x: .value("t", n.date),
                                  y: .value("y", useFahrenheit ? n.temperatureF : n.temperatureC))
                            .symbol { NowMarkerSymbol(color: seriesInk(.green)) }
                    }
                    if graphWetBulb {
                        PointMark(x: .value("t", n.date),
                                  y: .value("y", useFahrenheit ? n.wetBulbF : n.wetBulbC))
                            .symbol { NowMarkerSymbol(color: seriesInk(.blue)) }
                    }
                    if graphDewPoint {
                        PointMark(x: .value("t", n.date),
                                  y: .value("y", useFahrenheit ? n.dewPointF : n.dewPointC))
                            .symbol { NowMarkerSymbol(color: seriesInk(.red)) }
                    }
                    if graphFeels {
                        PointMark(x: .value("t", n.date),
                                  y: .value("y", useFahrenheit ? n.apparentTemperatureF
                                                               : n.apparentTemperatureC))
                            .symbol { NowMarkerSymbol(color: seriesInk(.purple)) }
                    }
                }
                nowRule
                scrubRule()
            }
            .chartLegend(.hidden)
            .chartYScale(domain: dom)
            .chartXScale(domain: visDomain)
            .chartYAxis { gridYAxis() }
            .chartXAxis { xAxis(labels: true) }
            .chartOverlay { proxy in scrubEntry(proxy) }
            .chartOverlay { proxy in if scrubDate != nil { scrubDragLayer(proxy) } }
            .chartOverlay { proxy in
                yAxisLabels(proxy, ticks: yTicks(dom.lowerBound, dom.upperBound, step: 5))
            }
            .overlay(alignment: scrubFraction < 0.5 ? .topTrailing : .topLeading) {
                if let p = scrubPoint {
                    scrubReadoutTop(p).padding(6).transition(.opacity)
                }
            }
            .frame(height: height - 20)
            .saturation(visionMode == .noColor ? 0 : graphPalette.saturation)
            .brightness(seriesBrightness)
        }
    }

    @ChartContentBuilder
    private func tempMark(_ date: Date, _ y: Double, _ color: Color, base: Double, key: String,
                          dash: [CGFloat] = []) -> some ChartContent {
        if linesOnly {
            LineMark(x: .value("t", date), y: .value("y", y), series: .value("s", key))
                .foregroundStyle(seriesInk(color))
                .lineStyle(SeriesDash.stroke(dash, patterned: patternedSeries))
                .interpolationMethod(.linear)
        } else {
            AreaMark(x: .value("t", date), yStart: .value("b", base), yEnd: .value("y", y),
                     series: .value("s", key))
                .foregroundStyle(seriesInk(color)).interpolationMethod(.linear)
        }
    }

    private var tempLegendDashes: [[CGFloat]] {
        guard patternedSeries else { return [] }
        var d: [[CGFloat]] = []
        if graphFeels    { d.append(SeriesDash.solid) }
        if graphTemp     { d.append(SeriesDash.dashed) }
        if graphWetBulb  { d.append(SeriesDash.dotted) }
        if graphDewPoint { d.append(SeriesDash.dashDot) }
        return d
    }

    private var windLegendDashes: [[CGFloat]] {
        guard patternedSeries else { return [] }
        var d: [[CGFloat]] = []
        if graphPrecip { d.append(SeriesDash.dotted) }
        if graphWind   { d.append(SeriesDash.solid) }
        if graphGust   { d.append([3, 2]) }
        return d
    }

    private var tempLegend: [(color: Color, label: String, isArea: Bool)] {
        var e: [(Color, String, Bool)] = []
        if graphFeels    { e.append((seriesInk(.purple), "Feels like", false)) }
        if graphTemp     { e.append((seriesInk(.green),  "Temp", false)) }
        if graphWetBulb  { e.append((seriesInk(.blue),   "Wet Bulb", false)) }
        if graphDewPoint { e.append((seriesInk(.red),    "Dew Pt", false)) }
        return e.map { ($0.0, $0.1, $0.2) }
    }

    // MARK: Precip / wind

    @ViewBuilder
    private func precipWindChart(height: CGFloat) -> some View {
        let hi = windYMax
        VStack(alignment: .leading, spacing: 2) {
            Chart {
                ForEach(allPoints) { p in
                    let gust = useFahrenheit ? p.windGustMPH : p.windGustKPH
                    let wind = useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH
                    let rain = p.precipProbability * 100
                    if graphGust && !linesOnly { windArea(p.date, gust, .red.opacity(0.35), "gA") }
                    if graphWind && !linesOnly { windArea(p.date, wind, .red, "wA") }
                    if graphPrecip {
                        if linesOnly {
                            LineMark(x: .value("t", p.date), y: .value("y", rain), series: .value("s", "rL"))
                                .foregroundStyle(seriesInk(.blue))
                                .lineStyle(SeriesDash.stroke(SeriesDash.dotted, patterned: patternedSeries))
                                .interpolationMethod(.linear)
                        } else {
                            windArea(p.date, rain, .blue, "rA")
                        }
                    }
                    if graphGust {
                        LineMark(x: .value("t", p.date), y: .value("y", gust), series: .value("s", "gL"))
                            .foregroundStyle(seriesInk(.red).opacity(patternedSeries ? 1 : 0.7)).lineStyle(StrokeStyle(lineWidth: 1.6, dash: [3, 2]))
                            .interpolationMethod(.linear)
                    }
                    if graphWind {
                        LineMark(x: .value("t", p.date), y: .value("y", wind), series: .value("s", "wL"))
                            .foregroundStyle(seriesInk(.red))
                            .lineStyle(SeriesDash.stroke(SeriesDash.solid, patterned: patternedSeries))
                            .interpolationMethod(.linear)
                    }
                }
                // Wind and gust get filled dots rather than rings, again as on
                // the 24-hour screen (there is no "now" precipitation to mark).
                if let n = nowPoint {
                    if graphGust {
                        PointMark(x: .value("t", n.date),
                                  y: .value("y", useFahrenheit ? n.windGustMPH : n.windGustKPH))
                            .foregroundStyle(seriesInk(.red).opacity(0.45)).symbolSize(90)
                    }
                    if graphWind {
                        PointMark(x: .value("t", n.date),
                                  y: .value("y", useFahrenheit ? n.windSpeedMPH : n.windSpeedKPH))
                            .foregroundStyle(seriesInk(.red)).symbolSize(90)
                    }
                }
                nowRule
                scrubRule()
            }
            .chartLegend(.hidden)
            .chartYScale(domain: linesOnly ? [0, hi] : [hi, 0])   // area mode hangs downward
            .chartXScale(domain: visDomain)
            .chartYAxis { gridYAxis() }
            .chartXAxis { xAxis(labels: true) }
            .chartOverlay { proxy in scrubEntry(proxy) }
            .chartOverlay { proxy in if scrubDate != nil { scrubDragLayer(proxy) } }
            .chartOverlay { proxy in
                yAxisLabels(proxy, ticks: yTicks(0, hi, step: hi > 60 ? 20 : 10))
            }
            // Wind/precip values sit over their own panel.
            .overlay(alignment: scrubFraction < 0.5 ? .topTrailing : .topLeading) {
                if let p = scrubPoint {
                    scrubReadoutBottom(p).padding(6).transition(.opacity)
                }
            }
            .frame(height: height - 20)
            .saturation(visionMode == .noColor ? 0 : graphPalette.saturation)
            .brightness(seriesBrightness)

            ChartLegendRow(entries: windLegend, dashes: windLegendDashes, ink: axisInk)
                .saturation(visionMode == .noColor ? 0 : graphPalette.saturation).padding(.leading, gutter)
        }
    }

    @ChartContentBuilder
    private func windArea(_ date: Date, _ y: Double, _ color: Color, _ key: String) -> some ChartContent {
        AreaMark(x: .value("t", date), yStart: .value("b", 0), yEnd: .value("y", y), series: .value("s", key))
            .foregroundStyle(seriesInk(color)).interpolationMethod(.linear)
    }

    private var windLegend: [(color: Color, label: String, isArea: Bool)] {
        var e: [(Color, String, Bool)] = []
        if graphPrecip { e.append((seriesInk(.blue), "Precip %", true)) }
        if graphWind   { e.append((seriesInk(.red), useFahrenheit ? "Wind mph" : "Wind kph", false)) }
        if graphGust   { e.append((seriesInk(.red).opacity(0.5), useFahrenheit ? "Gust mph" : "Gust kph", false)) }
        return e.map { ($0.0, $0.1, $0.2) }
    }

    // MARK: The folding color panel

    @ViewBuilder
    private func colorPanel(height: CGFloat) -> some View {
        let cols = dayCols
        let total = max(1, cols.count)
        VStack(alignment: .leading, spacing: 2) {
            Text(zoom > 0.5 ? "MyFeelsLike by time of day" : "MyFeelsLike by hour")
                .font(.caption2).foregroundStyle(axisInk).padding(.leading, gutter)
            if hasModel && comfortAsLineGraph {
                // A curve has no fold to perform: it simply keeps the shared
                // x-scale as the window widens, which is what the user asked
                // for — the graph shrinks, it does not rotate.
                comfortLineGraph.frame(height: height)
            } else if hasModel {
                Chart { PointMark(x: .value("t", visLo), y: .value("y", 0)).foregroundStyle(.clear) }
                    .chartXScale(domain: visDomain)
                    .chartYScale(domain: 0...1)
                    .chartYAxis(.hidden)
                    .chartXAxis(.hidden)
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            if let anchor = proxy.plotFrame {
                                foldCanvas(cols: cols, total: total, plot: geo[anchor])
                            }
                        }
                    }
                    // Long-press / drag on the color band scrubs it too.
                    .chartOverlay { proxy in scrubEntry(proxy) }
                    .chartOverlay { proxy in if scrubDate != nil { scrubDragLayer(proxy) } }
                    .frame(height: height)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(.regularMaterial)
                    .frame(height: height).padding(.leading, gutter)
                    .overlay(Text("No personalized color yet").font(.caption2))
            }
        }
    }

    /// Comfort as a curve against the named categories, for No color mode.
    /// Shares the fold's x-scale so it stays aligned with the charts above and
    /// below as the window widens from 24 hours to ten days.
    private var comfortLineGraph: some View {
        Chart {
            ForEach(allPoints) { p in
                if let v = p.myFeelsLikeShadeScore ?? p.myFeelsLikeScore {
                    LineMark(x: .value("t", p.date), y: .value("comfort", v),
                             series: .value("s", "shade"))
                        .foregroundStyle(axisInk).interpolationMethod(.linear)
                        .lineStyle(SeriesDash.stroke(SeriesDash.solid, patterned: true))
                }
                if sunFeatureActive, let v = p.myFeelsLikeSunScore {
                    LineMark(x: .value("t", p.date), y: .value("in sun", v),
                             series: .value("s", "sun"))
                        .foregroundStyle(axisInk).interpolationMethod(.linear)
                        .lineStyle(SeriesDash.stroke(SeriesDash.dashed, patterned: true))
                }
            }
            nowRule
            scrubRule()
        }
        .chartLegend(.hidden)
        .chartYScale(domain: ColorScale.minScore...ColorScale.maxScore)
        .chartXScale(domain: visDomain)
        .chartYAxis {
            AxisMarks(position: .leading,
                      values: ColorScale.comfortCategories.map(\.score)) { value in
                AxisGridLine().foregroundStyle(.gray.opacity(0.25))
                AxisValueLabel {
                    Text(ColorScale.categoryName(forScore: value.as(Double.self) ?? 0)
                            .replacingOccurrences(of: "very ", with: "v."))
                        .font(.system(size: 9)).foregroundStyle(axisInk)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartOverlay { proxy in scrubEntry(proxy) }
        .chartOverlay { proxy in if scrubDate != nil { scrubDragLayer(proxy) } }
    }

    private func foldCanvas(cols: [DayCol], total: Int, plot: CGRect) -> some View {
        let cal = Calendar.current
        // Show sun/shade whenever the model learned a sun effect. There is no
        // longer a style setting to consult: the band always splits into two
        // halves, so that width alone carries reliability everywhere.
        let splitSunShade = sunFeatureActive
        return Canvas { ctx, _ in
            // During the first layout pass (and while panels resize) the plot can
            // be empty or non-finite; drawing then feeds NaN to CoreGraphics.
            guard plot.isFinite, plot.width > 0, plot.height > 0 else { return }
            ctx.clip(to: Path(plot))   // keep the fold inside the plot area
            let midY = plot.midY
            let bandH = plot.height * 0.92
            let barTh = min(26, plot.height * 0.5)
            // Rotation belongs to the second stage only: the first stage just
            // widens the window, so the band thins without tipping over.
            let f = smoothstep(rotatePhase)
            let phi = f * .pi / 2

            for (_, col) in cols.enumerated() {
                let end = cal.date(byAdding: .day, value: 1, to: col.start) ?? col.start
                guard let xl = proxyX(col.start, plot: plot),
                      let xr = proxyX(end, plot: plot) else { continue }
                let colW = xr - xl
                if xr < plot.minX - 2 || xl > plot.maxX + 2 || colW <= 0 { continue }
                let colCenterX = (xl + xr) / 2
                let length = lerp(colW, bandH, f)
                let cross = lerp(barTh, colW, f)
                let cellW = length / 24
                guard colCenterX.isFinite, length.isFinite, cross > 0, cellW > 0 else { continue }

                ctx.drawLayer { layer in
                    // Deliberately *not* clipped to the day's own column. Doing
                    // that was what sliced the corners off a rotating band: a
                    // band of length L at angle phi sweeps L*cos(phi) + T*sin(phi)
                    // across, which is wider than its column mid-swing. Letting
                    // neighbours overlap keeps each band a whole rectangle, which
                    // reads as one object turning; the overlap resolves itself as
                    // the rotation completes. The panel-wide clip still applies,
                    // so nothing escapes into the charts above or below.
                    layer.translateBy(x: colCenterX, y: midY)
                    layer.rotate(by: .radians(-phi))     // hour 0 → bottom at f=1
                    for h in 0..<24 {
                        let localX = (CGFloat(h) + 0.5 - 12) * cellW
                        let color = col.scores[h].map { ColorScale.color(forScore: $0) } ?? Color.gray.opacity(0.4)
                        let sunColor = splitSunShade
                            ? col.sunScores[h].map { ColorScale.color(forScore: $0) }
                            : nil
                        // Reliability shrinks the cell across the strip. Because
                        // the strip rotates, that is the band's thickness at
                        // 24-hour and the cell's width inside its day column at
                        // 10-day — matching the paged screens at both ends.
                        let thick = cross * col.widths[h]
                        let rect = CGRect(x: localX - cellW / 2, y: -thick / 2,
                                          width: cellW + 0.5, height: thick)
                        guard rect.isFinite, thick > 0 else { continue }
                        if let sunColor {
                            // Shade first, sun second, across the strip's
                            // thickness. Because the strip rotates, that is two
                            // stacked bands at 24-hour and two halves of the day
                            // column at 10-day — the same split the paged screens
                            // draw, carried through the fold.
                            var top = rect, bottom = rect
                            top.size.height = rect.height / 2
                            bottom.origin.y = rect.midY
                            bottom.size.height = rect.height / 2
                            layer.fill(Path(top), with: .color(color))
                            layer.fill(Path(bottom), with: .color(sunColor))
                        } else {
                            layer.fill(Path(rect), with: .color(color))
                        }
                    }
                }
            }
            // Scrub line across the band, aligned with the charts above/below.
            if let t = scrubDate, let sx = proxyX(t, plot: plot), sx.isFinite {
                var line = Path()
                line.move(to: CGPoint(x: sx, y: plot.minY))
                line.addLine(to: CGPoint(x: sx, y: plot.maxY))
                ctx.stroke(line, with: .color(axisInk.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
    }

    /// Map a date to an absolute x within the overlay, using the shared x-scale.
    /// Returns nil rather than a non-finite value, which CoreGraphics rejects.
    private func proxyX(_ date: Date, plot: CGRect) -> CGFloat? {
        let lo = visLo.timeIntervalSinceReferenceDate
        let hi = visHi.timeIntervalSinceReferenceDate
        guard hi > lo, plot.isFinite else { return nil }
        let f = (date.timeIntervalSinceReferenceDate - lo) / (hi - lo)
        guard f.isFinite else { return nil }
        let x = plot.minX + CGFloat(f) * plot.width
        return x.isFinite ? x : nil
    }

    // MARK: Shared chart pieces

    private let gutter: CGFloat = 30

    /// "Now" marker: a solid grey line, so it reads differently from the dashed
    /// scrub line.
    @ChartContentBuilder
    private var nowRule: some ChartContent {
        if let nx = current?.date ?? series.first?.date {
            RuleMark(x: .value("now", nx))
                .foregroundStyle(.gray)
                .lineStyle(StrokeStyle(lineWidth: seriesLineWidth))
        }
    }

    /// Gridlines only. The numbers are drawn separately in `yAxisLabels`, on top
    /// of the marks — an axis value label sits *under* the plot, so a filled area
    /// reaching the left edge would hide it (and it left no gutter to sit in).
    private func gridYAxis() -> some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { _ in
            AxisGridLine().foregroundStyle(axisInk.opacity(0.22))
        }
    }

    /// Nice round tick values covering a range.
    private func yTicks(_ lo: Double, _ hi: Double, step: Double) -> [Double] {
        guard hi > lo, step > 0 else { return [] }
        var v = (lo / step).rounded(.up) * step
        var out: [Double] = []
        while v <= hi && out.count < 12 { out.append(v); v += step }
        return out
    }

    /// The y numbers, drawn above the plot so nothing can cover them. Outlined
    /// so they stay readable over the sky or over a filled area.
    private func yAxisLabels(_ proxy: ChartProxy, ticks: [Double]) -> some View {
        GeometryReader { geo in
            if let anchor = proxy.plotFrame {
                let plot = geo[anchor]
                if plot.isFinite, plot.height > 0 {
                    ForEach(ticks.filter { $0.isFinite }, id: \.self) { v in
                        if let y = proxy.position(forY: v), y.isFinite {
                            OutlinedNumber(text: "\(Int(v.rounded()))",
                                           fill: axisInk,
                                           halo: axisInk == .white ? .black : .white)
                                .position(x: plot.minX + 14, y: plot.minY + y)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func xAxis(labels: Bool) -> some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 9)) { value in
            AxisGridLine().foregroundStyle(axisInk.opacity(0.22))
            AxisTick().foregroundStyle(axisInk.opacity(0.55))
            if labels {
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(xLabel(d)).font(.caption2).foregroundStyle(axisInk)
                    }
                }
            }
        }
    }

    /// Hour label when zoomed in; once the window spans days, the day of the
    /// month — with the weekday too when the axis is wide enough for both. A
    /// bare weekday stops identifying a day once the window can scroll across
    /// weeks.
    private func xLabel(_ d: Date) -> String {
        let visible = visHi.timeIntervalSince(visLo)
        if visible <= 2 * 86400 {
            return clockHourLabel(Calendar.current.component(.hour, from: d), use12: use12Hour)
        }
        return dayTickLabel(d, includeWeekday: dayAxisFitsWeekday(
            plotWidth: plotWidth, days: visible / 86400))
    }
}

// MARK: - Outlined axis number (legible over sky or a filled area)

private struct OutlinedNumber: View {
    let text: String
    let fill: Color
    let halo: Color
    var body: some View {
        ZStack {
            // 12 offsets give a solid halo, so the fill reads as its true color
            // (a sparse halo bleeds through and makes black look grey).
            ForEach(0..<12, id: \.self) { i in
                let a = Double(i) / 12 * 2 * .pi
                Text(text).foregroundStyle(halo)
                    .offset(x: 1.4 * cos(a), y: 1.4 * sin(a))
            }
            Text(text).foregroundStyle(fill)
        }
        .font(.caption.weight(.semibold))
    }
}

// MARK: - helpers

private extension CGRect {
    /// CoreGraphics rejects NaN/infinite geometry (and logs about it), which can
    /// otherwise slip in from a zero-size layout pass.
    var isFinite: Bool {
        origin.x.isFinite && origin.y.isFinite && size.width.isFinite && size.height.isFinite
    }
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
private func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, x)) }
private func smoothstep(_ x: Double) -> Double { let c = clamp(x, 0, 1); return c * c * (3 - 2 * c) }
