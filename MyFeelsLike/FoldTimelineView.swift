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

    /// 0 = 24-hour view, 1 = 10-day view. Animated by the segmented control.
    @State private var progress: Double = 0

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

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            if allPoints.isEmpty {
                ForecastLoadingView(progress: progressLoad, nowTick: nowTick, errorMessage: errorMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    ScenarioStrip(activeFeatures: activeFeatures)
                    modePicker
                    if tempVisible { temperatureChart(height: h * 0.42) }
                    if graphColor { colorPanel(height: h * 0.20) }
                    if windVisible { precipWindChart(height: h * 0.30) }
                    if let attribution { WeatherAttributionLink(info: attribution) }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal)
                .refreshable { await onRefresh?() }
            }
        }
    }

    private var modePicker: some View {
        Picker("View", selection: Binding(
            get: { progress > 0.5 },
            set: { tenDay in withAnimation(.easeInOut(duration: 1.0)) { progress = tenDay ? 1 : 0 } }
        )) {
            Text("24-hour").tag(false)
            Text("10-day").tag(true)
        }
        .pickerStyle(.segmented)
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
            }
            .chartLegend(.hidden)
            .chartYScale(domain: dom)
            .chartXScale(domain: visDomain)
            .chartYAxis { leadingYAxis(stride: 5) }
            .chartXAxis { xAxis(labels: true) }
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
            }
            .chartLegend(.hidden)
            .chartYScale(domain: linesOnly ? [0, hi] : [hi, 0])   // area mode hangs downward
            .chartXScale(domain: visDomain)
            .chartYAxis { leadingYAxis(stride: nil) }
            .chartXAxis { xAxis(labels: true) }
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
                    .chartYAxis { leadingYAxis(clear: true) }
                    .chartXAxis(.hidden)
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            if let anchor = proxy.plotFrame {
                                foldCanvas(cols: cols, total: total, plot: geo[anchor])
                            }
                        }
                    }
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

    @ChartContentBuilder
    private var nowRule: some ChartContent {
        if let nx = current?.date ?? series.first?.date {
            RuleMark(x: .value("now", nx))
                .foregroundStyle(axisInk.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    @AxisContentBuilder
    private func leadingYAxis(stride: Int? = nil, clear: Bool = false) -> some AxisContent {
        if clear {
            // A clear label reserves the same leading width as the temp/wind
            // charts so the color panel lines up with them.
            AxisMarks(position: .leading, values: [0.0]) { _ in
                AxisValueLabel { Text("00").font(.caption).foregroundStyle(.clear) }
            }
        } else {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(axisInk.opacity(0.22))
                AxisTick().foregroundStyle(axisInk.opacity(0.55))
                AxisValueLabel().font(.caption).foregroundStyle(axisInk)
            }
        }
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

// MARK: - helpers

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
private func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, x)) }
private func smoothstep(_ x: Double) -> Double { let c = clamp(x, 0, 1); return c * c * (3 - 2 * c) }
