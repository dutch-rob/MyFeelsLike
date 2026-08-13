// SPDX-License-Identifier: GPL-3.0-or-later
//
//  FoldTimelineView.swift
//  MyFeelsLike
//
//  Optional "integrated fold" view (Settings → Timeline fold). Instead of
//  paging between a 24-hour screen and a 10-day screen, one continuous timeline
//  morphs between them: a segmented control drives a progress value 0…1, and
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

    /// 0 = 24-hour view, 1 = 10-day view. Scrubbed by a horizontal swipe.
    @State private var progress: Double = 0
    /// Progress captured at the start of the current swipe (nil when not dragging).
    @State private var dragBase: Double? = nil
    /// The time the user is reading via long-press scrub (nil = not scrubbing).
    /// While set, the transition swipe is suspended and a readout is shown.
    @State private var scrubDate: Date? = nil
    /// The plots' on-screen (global) x-range, so a long press in the gaps between
    /// panels can be mapped to a time too.
    @State private var plotXRange: ClosedRange<CGFloat>? = nil

    private var linesOnly: Bool { chartStyle == .lines }
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
    }

    private var dayCols: [DayCol] {
        let cal = Calendar.current
        var byDay: [Date: [Int: (Double, Double)]] = [:]
        for p in allPoints {
            guard let s = p.myFeelsLikeScore else { continue }
            let d = cal.startOfDay(for: p.date)
            let h = cal.component(.hour, from: p.date)
            byDay[d, default: [:]][h] = (s, myFeelsLikeReliability(p))
        }
        return byDay.keys.sorted().map { d in
            let row = byDay[d]
            return DayCol(start: d,
                          scores: (0..<24).map { row?[$0]?.0 },
                          widths: (0..<24).map { row?[$0]?.1 ?? 1 })
        }
    }

    private var hasModel: Bool { allPoints.contains { $0.myFeelsLikeScore != nil } }

    // MARK: Time domain (interpolated by progress)

    /// Narrow (24-hour) window: a rolling day starting at "now", so it's always
    /// full — matching the 24-hour screen rather than the calendar day (whose
    /// morning is in the past and has no forecast).
    private var narrowLo: Date { current?.date ?? series.first?.date ?? nowTick }
    private var narrowHi: Date { narrowLo.addingTimeInterval(24 * 3600) }
    private var fullLo: Date { allPoints.first?.date ?? narrowLo }
    private var fullHi: Date { series.last?.date ?? narrowHi }

    /// End of the first stage: the whole preceding day is in view and the
    /// forecast reaches +72 h. Up to here the swipe only widens the window (the
    /// color band just gets thinner as each hour claims less width); past it the
    /// band starts rotating into the heat map.
    private let foldSplit = 0.4
    /// Where the first stage stops zooming to: 72 hours ahead of "now".
    private var midHi: Date { narrowLo.addingTimeInterval(72 * 3600) }

    /// 0…1 through the widening stage.
    private var zoomPhase: Double { min(1, progress / foldSplit) }
    /// 0…1 through the rotating stage (0 until the widening stage is done).
    private var rotatePhase: Double { max(0, (progress - foldSplit) / (1 - foldSplit)) }

    private func lerpDate(_ a: Date, _ b: Date, _ t: Double) -> Date {
        Date(timeIntervalSinceReferenceDate:
                a.timeIntervalSinceReferenceDate
                + (b.timeIntervalSinceReferenceDate - a.timeIntervalSinceReferenceDate) * t)
    }
    /// The past comes in during the first stage only, so by the time +72 h is on
    /// screen the preceding day is fully there and stays put while the rest of
    /// the forecast arrives.
    private var visLo: Date { lerpDate(narrowLo, fullLo, zoomPhase) }
    private var visHi: Date {
        progress <= foldSplit ? lerpDate(narrowHi, midHi, zoomPhase)
                              : lerpDate(midHi, fullHi, rotatePhase)
    }
    private var visDomain: ClosedRange<Date> { visLo...max(visLo.addingTimeInterval(3600), visHi) }

    // MARK: Y ranges (over all data, stable while zooming)

    private var tempYDomain: ClosedRange<Double> {
        var v: [Double] = []
        for p in allPoints {
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
        for p in allPoints {
            if graphPrecip { v.append(p.precipProbability * 100) }
            if graphGust   { v.append(useFahrenheit ? p.windGustMPH : p.windGustKPH) }
            if graphWind   { v.append(useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH) }
        }
        let hi = v.max() ?? 1
        return hi + max(1, hi * 0.08)
    }

    private var skyIsDay: Bool {
        if let sr = sunrise, let ss = sunset { return nowTick >= sr && nowTick < ss }
        return (series.first ?? current)?.isDaylight ?? true
    }
    private var axisInk: Color { graphSky ? (skyIsDay ? .black : .white) : .primary }

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
                let colorH = lerp(avail * 0.10, avail * 0.34, smoothstep(rotatePhase))
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
                    .gesture(scrubGesture(width: geo.size.width))
                }
                .refreshable { await onRefresh?() }
            }
        }
    }

    /// Thin swipe hint (replaces the segmented control to give the graphs room).
    /// Since the swipe can now rest anywhere, an end label is only emphasised
    /// when the view is actually at that end; in between, both are dimmed and a
    /// span readout says how much of the forecast is on screen.
    private var modeIndicator: some View {
        let atStart = progress < 0.05, atEnd = progress > 0.95
        return HStack(spacing: 8) {
            Text("24-hour").fontWeight(atStart ? .semibold : .regular)
                .foregroundStyle(atStart ? axisInk : axisInk.opacity(0.5))
            if atStart || atEnd {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption2).foregroundStyle(axisInk.opacity(0.5))
            } else {
                Text(spanLabel)
                    .font(.caption2).foregroundStyle(axisInk.opacity(0.75))
                    .monospacedDigit()
            }
            Text("10-day").fontWeight(atEnd ? .semibold : .regular)
                .foregroundStyle(atEnd ? axisInk : axisInk.opacity(0.5))
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
    }

    /// How much time the visible window covers, for intermediate zoom levels.
    private var spanLabel: String {
        let hours = visHi.timeIntervalSince(visLo) / 3600
        if hours < 48 { return "\(Int(hours.rounded())) h" }
        return "\(Int((hours / 24).rounded())) days"
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                guard scrubDate == nil else { return }   // scrubbing: line is moved by the chart drag layer
                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                if dragBase == nil { dragBase = progress }
                let span = max(1, width * 0.7)
                progress = clamp((dragBase ?? progress) - v.translation.width / span, 0, 1)
            }
            .onEnded { v in
                guard scrubDate == nil else { return }
                let span = max(1, width * 0.7)
                // Rest wherever the swipe lands (with a little momentum) rather
                // than snapping to 24-hour or 10-day, so any intermediate zoom
                // is a resting state. Snapping back is a one-line change if the
                // in-between views don't read well.
                let projected = clamp((dragBase ?? progress) - v.predictedEndTranslation.width / span, 0, 1)
                withAnimation(.easeOut(duration: 0.25)) { progress = projected }
                dragBase = nil
            }
    }

    // MARK: Temperature

    @ViewBuilder
    private func temperatureChart(height: CGFloat) -> some View {
        let dom = tempYDomain
        let base = dom.lowerBound
        VStack(alignment: .leading, spacing: 2) {
            ChartLegendRow(entries: tempLegend, ink: axisInk).padding(.leading, gutter)
            Chart {
                ForEach(allPoints) { p in
                    let dry = useFahrenheit ? p.temperatureF : p.temperatureC
                    let wet = useFahrenheit ? p.wetBulbF : p.wetBulbC
                    let dew = useFahrenheit ? p.dewPointF : p.dewPointC
                    let app = useFahrenheit ? p.apparentTemperatureF : p.apparentTemperatureC
                    if graphTemp     { tempMark(p.date, dry, .green, base: base, key: "dry") }
                    if graphWetBulb  { tempMark(p.date, wet, .blue,  base: base, key: "wet") }
                    if graphDewPoint { tempMark(p.date, dew, .red,   base: base, key: "dew") }
                    if graphFeels {
                        LineMark(x: .value("t", p.date), y: .value("app", app), series: .value("s", "app"))
                            .foregroundStyle(.purple).lineStyle(StrokeStyle(lineWidth: 1.5))
                            .interpolationMethod(.linear)
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
            .saturation(graphPalette.saturation)
        }
    }

    @ChartContentBuilder
    private func tempMark(_ date: Date, _ y: Double, _ color: Color, base: Double, key: String) -> some ChartContent {
        if linesOnly {
            LineMark(x: .value("t", date), y: .value("y", y), series: .value("s", key))
                .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.5)).interpolationMethod(.linear)
        } else {
            AreaMark(x: .value("t", date), yStart: .value("b", base), yEnd: .value("y", y),
                     series: .value("s", key))
                .foregroundStyle(color).interpolationMethod(.linear)
        }
    }

    private var tempLegend: [(color: Color, label: String, isArea: Bool)] {
        var e: [(Color, String, Bool)] = []
        if graphFeels    { e.append((.purple, "Feels like", false)) }
        if graphTemp     { e.append((.green,  "Temp", false)) }
        if graphWetBulb  { e.append((.blue,   "Wet Bulb", false)) }
        if graphDewPoint { e.append((.red,    "Dew Pt", false)) }
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
                                .foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 1.5)).interpolationMethod(.linear)
                        } else {
                            windArea(p.date, rain, .blue, "rA")
                        }
                    }
                    if graphGust {
                        LineMark(x: .value("t", p.date), y: .value("y", gust), series: .value("s", "gL"))
                            .foregroundStyle(.red.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1.6, dash: [3, 2]))
                            .interpolationMethod(.linear)
                    }
                    if graphWind {
                        LineMark(x: .value("t", p.date), y: .value("y", wind), series: .value("s", "wL"))
                            .foregroundStyle(.red).interpolationMethod(.linear)
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
            .saturation(graphPalette.saturation)

            ChartLegendRow(entries: windLegend, ink: axisInk).padding(.leading, gutter)
        }
    }

    @ChartContentBuilder
    private func windArea(_ date: Date, _ y: Double, _ color: Color, _ key: String) -> some ChartContent {
        AreaMark(x: .value("t", date), yStart: .value("b", 0), yEnd: .value("y", y), series: .value("s", key))
            .foregroundStyle(color).interpolationMethod(.linear)
    }

    private var windLegend: [(color: Color, label: String, isArea: Bool)] {
        var e: [(Color, String, Bool)] = []
        if graphPrecip { e.append((.blue, "Precip %", true)) }
        if graphWind   { e.append((.red, useFahrenheit ? "Wind mph" : "Wind kph", false)) }
        if graphGust   { e.append((.red.opacity(0.5), useFahrenheit ? "Gust mph" : "Gust kph", false)) }
        return e.map { ($0.0, $0.1, $0.2) }
    }

    // MARK: The folding color panel

    @ViewBuilder
    private func colorPanel(height: CGFloat) -> some View {
        let cols = dayCols
        let total = max(1, cols.count)
        VStack(alignment: .leading, spacing: 2) {
            Text(progress > 0.5 ? "MyFeelsLike by time of day" : "MyFeelsLike by hour")
                .font(.caption2).foregroundStyle(axisInk).padding(.leading, gutter)
            if hasModel {
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

    private func foldCanvas(cols: [DayCol], total: Int, plot: CGRect) -> some View {
        let cal = Calendar.current
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
                        // Reliability shrinks the cell across the strip. Because
                        // the strip rotates, that is the band's thickness at
                        // 24-hour and the cell's width inside its day column at
                        // 10-day — matching the paged screens at both ends.
                        let thick = cross * col.widths[h]
                        let rect = CGRect(x: localX - cellW / 2, y: -thick / 2,
                                          width: cellW + 0.5, height: thick)
                        guard rect.isFinite, thick > 0 else { continue }
                        layer.fill(Path(rect), with: .color(color))
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
                .lineStyle(StrokeStyle(lineWidth: 1.5))
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
        AxisMarks(values: .automatic(desiredCount: 6)) { value in
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

    /// Hour label when zoomed in, weekday when zoomed out.
    private func xLabel(_ d: Date) -> String {
        let span = visHi.timeIntervalSince(visLo)
        let cal = Calendar.current
        if span <= 2 * 86400 {
            return clockHourLabel(cal.component(.hour, from: d), use12: use12Hour)
        }
        let f = DateFormatter(); f.locale = .current; f.dateFormat = "EEE"
        return String(f.string(from: d).prefix(2))
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
