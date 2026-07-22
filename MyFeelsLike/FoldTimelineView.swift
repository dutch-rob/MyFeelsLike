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

    private var linesOnly: Bool { chartStyle == .lines }
    private var tempVisible: Bool { graphTemp || graphWetBulb || graphDewPoint || graphFeels }
    private var windVisible: Bool { graphPrecip || graphWind || graphGust }

    // MARK: Data

    private var allPoints: [ForecastPoint] {
        (historic + (current.map { [$0] } ?? []) + series).sorted { $0.date < $1.date }
    }

    /// One calendar day of hourly scores (nil where no point/no model).
    private struct DayCol { let start: Date; let scores: [Double?] }

    private var dayCols: [DayCol] {
        let cal = Calendar.current
        var byDay: [Date: [Int: Double]] = [:]
        for p in allPoints {
            guard let s = p.myFeelsLikeScore else { continue }
            let d = cal.startOfDay(for: p.date)
            let h = cal.component(.hour, from: p.date)
            byDay[d, default: [:]][h] = s
        }
        return byDay.keys.sorted().map { d in
            DayCol(start: d, scores: (0..<24).map { byDay[d]?[$0] })
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

    private func lerpDate(_ a: Date, _ b: Date, _ t: Double) -> Date {
        Date(timeIntervalSinceReferenceDate:
                a.timeIntervalSinceReferenceDate
                + (b.timeIntervalSinceReferenceDate - a.timeIntervalSinceReferenceDate) * t)
    }
    private var visLo: Date { lerpDate(narrowLo, fullLo, progress) }
    private var visHi: Date { lerpDate(narrowHi, fullHi, progress) }
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

    /// Long press drops the line where the finger is (the last touch recorded by
    /// the passive recogniser), falling back to the middle of the window. The
    /// drag layer then moves it. While scrubbing, the transition swipe is off.
    private func enterScrub(atX x: CGFloat?, width: CGFloat) {
        guard scrubDate == nil, !allPoints.isEmpty else { return }
        let lo = visLo.timeIntervalSinceReferenceDate
        let hi = visHi.timeIntervalSinceReferenceDate
        let frac: Double
        if let x {
            // Approximate plot bounds: horizontal padding + the y-axis gutter.
            let left: CGFloat = 46, right = max(left + 1, width - 16)
            frac = Double(min(1, max(0, (x - left) / (right - left))))
        } else {
            frac = 0.5
        }
        let target = Date(timeIntervalSinceReferenceDate: lo + frac * (hi - lo))
        scrubDate = allPoints.min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }?.date
    }

    /// Active only while scrubbing: any touch/drag on a panel moves the line, and
    /// a tap (press with no movement) dismisses it.
    @ViewBuilder
    private func scrubDragLayer(_ proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle().fill(Color.clear).contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard let pf = proxy.plotFrame else { return }
                            let x = v.location.x - geo[pf].origin.x
                            if let d = proxy.value(atX: x, as: Date.self) {
                                scrubDate = allPoints.min {
                                    abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d))
                                }?.date
                            }
                        }
                        .onEnded { v in
                            if abs(v.translation.width) < 6 && abs(v.translation.height) < 6 {
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
                Text(scrubTimeLabel(p.date)).font(.caption2.weight(.semibold))
                Image(systemName: p.symbolName).font(.caption2)
                if let s = p.myFeelsLikeScore {
                    let c = max(ColorScale.minScore, min(ColorScale.maxScore, s))
                    Text(String(format: "%.0f", c))
                        .font(.caption2.weight(.bold)).monospacedDigit()
                        .foregroundStyle(ColorScale.contrastingText(forScore: c))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(ColorScale.color(forScore: c), in: RoundedRectangle(cornerRadius: 3))
                }
                Spacer(minLength: 10)
                Button { scrubDate = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.callout).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            readoutRow("Temp/feels \(unit)",
                       String(format: "%.1f (%.1f)",
                              useFahrenheit ? p.temperatureF : p.temperatureC,
                              useFahrenheit ? p.apparentTemperatureF : p.apparentTemperatureC), .green)
            readoutRow("Wet bulb \(unit)", String(format: "%.1f", useFahrenheit ? p.wetBulbF : p.wetBulbC), .blue)
            readoutRow("Dew pt \(unit)", String(format: "%.1f", useFahrenheit ? p.dewPointF : p.dewPointC), .red)
            readoutRow("UV", String(format: "%.0f", p.uvIndex), .orange)
            readoutRow("Cloud %", String(format: "%.0f (l:%.0f m:%.0f h:%.0f)",
                                         p.cloudCover * 100, p.cloudCoverLow * 100,
                                         p.cloudCoverMedium * 100, p.cloudCoverHigh * 100), .secondary)
        }
    }

    /// Values that belong to the precip/wind panel (shown over it).
    private func scrubReadoutBottom(_ p: ForecastPoint) -> some View {
        let windUnit = useFahrenheit ? "mph" : "kph"
        return readoutCard {
            readoutRow("Wind (gust) \(windUnit)",
                       String(format: "%.0f (%.0f)",
                              useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH,
                              useFahrenheit ? p.windGustMPH : p.windGustKPH), .red)
            readoutRow("Precip", String(format: "%.1f mm (%.0f%%)",
                                        p.precipitationMM, p.precipProbability * 100), .blue)
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
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).font(.caption2.weight(.medium)).monospacedDigit()
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
                let colorH = lerp(avail * 0.10, avail * 0.34, progress)
                let graphsH = avail - colorH
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
                .contentShape(Rectangle())
                // NOTE: do not add another touch recogniser here. A
                // simultaneousGesture(DragGesture(minimumDistance: 0)) — tried in
                // order to capture the press location — claims the touch on
                // touch-down and killed both the transition swipe and the long
                // press. The line therefore starts mid-window; a tap moves it.
                .onLongPressGesture(minimumDuration: 0.35) {
                    enterScrub(atX: nil, width: geo.size.width)
                }
                .gesture(scrubGesture(width: geo.size.width))
            }
        }
    }

    /// Thin swipe hint (replaces the segmented control to give the graphs room).
    private var modeIndicator: some View {
        HStack(spacing: 8) {
            Text("24-hour").fontWeight(progress < 0.5 ? .semibold : .regular)
                .foregroundStyle(progress < 0.5 ? axisInk : axisInk.opacity(0.5))
            Image(systemName: "arrow.left.arrow.right").font(.caption2).foregroundStyle(axisInk.opacity(0.5))
            Text("10-day").fontWeight(progress >= 0.5 ? .semibold : .regular)
                .foregroundStyle(progress >= 0.5 ? axisInk : axisInk.opacity(0.5))
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
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
                let projected = clamp((dragBase ?? progress) - v.predictedEndTranslation.width / span, 0, 1)
                withAnimation(.easeOut(duration: 0.3)) { progress = projected > 0.5 ? 1 : 0 }
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
                    // Dragging on the color band moves the scrub line too.
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
            ctx.clip(to: Path(plot))   // keep the fold inside the plot area
            let midY = plot.midY
            let bandH = plot.height * 0.92
            let barTh = min(26, plot.height * 0.5)
            // Fold tracks the overall progress (not column width) so the swing is
            // visible across the whole transition, matched to the charts' zoom.
            let f = smoothstep(progress)
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

                ctx.drawLayer { layer in
                    // Keep each day's fold inside its own column so half-folded
                    // bands don't cross into their neighbours.
                    layer.clip(to: Path(CGRect(x: xl, y: plot.minY, width: colW, height: plot.height)))
                    layer.translateBy(x: colCenterX, y: midY)
                    layer.rotate(by: .radians(-phi))     // hour 0 → bottom at f=1
                    for h in 0..<24 {
                        let localX = (CGFloat(h) + 0.5 - 12) * cellW
                        let color = col.scores[h].map { ColorScale.color(forScore: $0) } ?? Color.gray.opacity(0.4)
                        let rect = CGRect(x: localX - cellW / 2, y: -cross / 2, width: cellW + 0.5, height: cross)
                        layer.fill(Path(rect), with: .color(color))
                    }
                }
            }
            // Scrub line across the band, aligned with the charts above/below.
            if let t = scrubDate, let sx = proxyX(t, plot: plot) {
                var line = Path()
                line.move(to: CGPoint(x: sx, y: plot.minY))
                line.addLine(to: CGPoint(x: sx, y: plot.maxY))
                ctx.stroke(line, with: .color(axisInk.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
    }

    /// Map a date to an absolute x within the overlay, using the shared x-scale.
    private func proxyX(_ date: Date, plot: CGRect) -> CGFloat? {
        let lo = visLo.timeIntervalSinceReferenceDate
        let hi = visHi.timeIntervalSinceReferenceDate
        guard hi > lo else { return nil }
        let f = (date.timeIntervalSinceReferenceDate - lo) / (hi - lo)
        return plot.minX + CGFloat(f) * plot.width
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
                ForEach(ticks, id: \.self) { v in
                    if let y = proxy.position(forY: v) {
                        OutlinedNumber(text: "\(Int(v.rounded()))",
                                       fill: axisInk,
                                       halo: axisInk == .white ? .black : .white)
                            .position(x: plot.minX + 14, y: plot.minY + y)
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

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
private func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, x)) }
private func smoothstep(_ x: Double) -> Double { let c = clamp(x, 0, 1); return c * c * (3 - 2 * c) }
