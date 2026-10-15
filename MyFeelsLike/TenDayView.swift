// SPDX-License-Identifier: GPL-3.0-or-later
//
//  TenDayView.swift
//  MyFeelsLike
//
//  The 10-day screen: temperature bands (dashed history + solid forecast), the
//  MyFeelsLike time-of-day heatmap, and the precip/wind chart.
//

import SwiftUI
import Charts

// MARK: - TenDayView

struct TenDayView: View {
    var series: [ForecastPoint]

    /// Left edge of the visible time window. nil = show the whole series (the
    /// pre-scrolling behaviour, still used by the iPad dashboard). When set,
    /// the charts pan over the −10d…+10d series instead of a fixed slice.
    /// `series`/`historic` are already sliced to it by the caller; this fixes
    /// the axis so the window stays put as the data shifts under it.
    var windowStart: Date? = nil
    /// How much time the window covers.
    var windowSpan: TimeInterval = 240 * 3600

    /// The window as a range, if scrolling is active.
    private var visibleRange: ClosedRange<Date>? {
        guard let s = windowStart else { return nil }
        // A sliver of lead-in, proportional to the window, so the "now" ring
        // sits inside the plot instead of being clipped by its left edge.
        return s.addingTimeInterval(-windowSpan * 0.03)...s.addingTimeInterval(windowSpan)
    }

    /// Plot width, kept so the day axis can decide whether the weekday fits.
    @State private var plotWidth: CGFloat = 0
    /// Observed past ~24 h, drawn dashed to the left of the forecast.
    var historic: [ForecastPoint] = []
    /// "now" boundary point joining the dashed history to the solid forecast.
    var current: ForecastPoint? = nil
    var progress: LoadProgress = LoadProgress()
    var nowTick: Date = .now
    /// Today's precise sunrise/sunset (WeatherKit); drives the day↔night switch.
    var sunrise: Date? = nil
    var sunset: Date? = nil
    var errorMessage: String? = nil
    var attribution: WeatherAttributionInfo? = nil
    var onRefresh: (() async -> Void)? = nil
    /// Features currently in the regression model. Used to decide which
    /// scenario adjusters to show. Empty = no model, no chips shown.
    var activeFeatures: Set<Feature> = []
    /// Plain-language reasons there's no personalized model yet (empty when one
    /// exists). Shown on the gray heatmap panel.
    var modelReasons: [String] = []
    /// True when embedded in a fixed-height dashboard pane (iPad): panel
    /// fractions shrink so everything fits without scrolling.
    var fitsPane: Bool = false
    /// Use the landscape arrangement even in a nominally regular height — see
    /// HereTodayView.forceLandscapeLayout.
    var forceLandscapeLayout: Bool = false

    @AppStorage(SettingsKey.useFahrenheit) private var useFahrenheit: Bool = true
    @AppStorage(SettingsKey.use12HourClock) private var use12Hour = false
    @AppStorage(GraphKey.temp)     private var graphTemp     = true
    @AppStorage(GraphKey.wetBulb)  private var graphWetBulb  = false
    @AppStorage(GraphKey.dewPoint) private var graphDewPoint = false
    @AppStorage(GraphKey.feels)    private var graphFeels    = true
    @AppStorage(GraphKey.color)   private var graphColor   = true
    @AppStorage(GraphKey.precip)   private var graphPrecip   = true
    @AppStorage(GraphKey.wind)     private var graphWind     = true
    @AppStorage(GraphKey.gust)     private var graphGust     = true
    @AppStorage(GraphKey.sky)      private var graphSky      = true
    @AppStorage(SettingsKey.colorVisionMode)
    private var visionMode = ColorScale.ColorVisionMode.full
    @AppStorage(SettingsKey.noColorStyle)
    private var noColorStyle = ColorScale.NoColorStyle.lineGraph
    /// Curves need dash patterns to be told apart once hue carries nothing.
    private var patternedSeries: Bool { visionMode == .noColor }
    private var comfortAsLineGraph: Bool {
        visionMode == .noColor && noColorStyle == .lineGraph
    }
    @AppStorage(SettingsKey.chartSeriesStyle) private var chartStyle = ChartSeriesStyle.lines
    @AppStorage(SettingsKey.graphPalette) private var graphPalette = GraphPalette.vivid
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var linesOnly: Bool { chartStyle == .lines }

    /// The time the user is scrubbing to after a long-press on a chart. A dashed
    /// vertical line is drawn at this time across every panel, and a readout card
    /// (the "table row" for that hour) is shown. nil = not scrubbing.
    @State private var scrubDate: Date? = nil
    /// Plots' on-screen (global) x-range, so a long press between panels maps too.
    @State private var plotXRange: ClosedRange<CGFloat>? = nil

    private var tempPanelVisible: Bool { graphTemp || graphWetBulb || graphDewPoint || graphFeels }
    private var colorPanelVisible: Bool { graphColor }
    private var windPanelVisible: Bool { graphPrecip || graphWind || graphGust }

    /// Ink for a weather curve. In No color mode every curve is drawn in the
    /// same ink and told apart by its dash pattern, so hue carries nothing at
    /// all -- previously they were desaturated to *different* grays, which is
    /// still a lightness code. Follows the sky like the axes do: literal black
    /// would be invisible against the night background.
    private func seriesInk(_ base: Color) -> Color {
        patternedSeries ? axisInk : base
    }

    private func panelHeights(_ h: CGFloat) -> (temp: CGFloat, color: CGFloat, wind: CGFloat) {
        let wT = tempPanelVisible ? 0.42 : 0
        // The heatmap was taking nearly a third of the screen and crowding the
        // curves; a third less suits it, and the other two panels take up the
        // slack through the normalisation below.
        let wC = colorPanelVisible ? 0.21 : 0
        let wW = windPanelVisible ? 0.32 : 0
        let tot = wT + wC + wW
        guard tot > 0 else { return (0, 0, 0) }
        // usable < 1 leaves room for the three panel labels + scenario strip +
        // attribution so the bottom panel's x-axis isn't clipped. Beside the
        // table there is no scenario strip to leave room for — the chips moved
        // up to the title row — so the panels there take that share back.
        let usable = h * (fitsPane ? 0.96 : 0.82)
        return (usable * wT / tot, usable * wC / tot, usable * wW / tot)
    }

    private var tempLegendEntries: [(color: Color, label: String, isArea: Bool)] {
        var e: [(color: Color, label: String, isArea: Bool)] = []
        if graphFeels    { e.append((seriesInk(.purple), "Feels like", false)) }
        if graphTemp     { e.append((seriesInk(.green),  "Temp",        false)) }
        if graphWetBulb  { e.append((seriesInk(.blue),   "Wet Bulb",    false)) }
        if graphDewPoint { e.append((seriesInk(.red),    "Dew Pt",      false)) }
        return e
    }

    /// Dash patterns matching the curves, parallel to the legend entries.
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
        if graphGust   { d.append([4, 3]) }
        return d
    }

    private var windLegendEntries: [(color: Color, label: String, isArea: Bool)] {
        var e: [(color: Color, label: String, isArea: Bool)] = []
        if graphPrecip { e.append((seriesInk(.blue), "Precip %", true)) }
        if graphWind   { e.append((seriesInk(.red),  useFahrenheit ? "Wind mph" : "Wind kph", false)) }
        if graphGust   { e.append((seriesInk(.red).opacity(0.5), useFahrenheit ? "Gust mph" : "Gust kph", false)) }
        return e
    }

    /// Whether the forecast carries personalized feels-like scores.
    private var hasModel: Bool {
        allPoints.contains { $0.myFeelsLikeScore != nil }
    }

    /// Historic + "now", used for the dashed past line.
    private var historicPlus: [ForecastPoint] {
        historic + (current.map { [$0] } ?? [])
    }
    /// "now" + forecast, used for the solid future line (joins at "now").
    private var forecastPlus: [ForecastPoint] {
        (current.map { [$0] } ?? []) + series
    }
    /// All plotted points oldest→newest, for the MyFeelsLike color background.
    private var allPoints: [ForecastPoint] {
        historic + (current.map { [$0] } ?? []) + series
    }

    /// Tight y-range over all temperature curves, used as the explicit scale so
    /// the forecast's filled bands have a defined baseline.
    private var tempYDomain: ClosedRange<Double> {
        var vals: [Double] = []
        for p in allPoints {
            if graphTemp     { vals.append(useFahrenheit ? p.temperatureF : p.temperatureC) }
            if graphWetBulb  { vals.append(useFahrenheit ? p.wetBulbF : p.wetBulbC) }
            if graphDewPoint { vals.append(useFahrenheit ? p.dewPointF : p.dewPointC) }
            if graphFeels    { vals.append(useFahrenheit ? p.apparentTemperatureF : p.apparentTemperatureC) }
        }
        guard let lo = vals.min(), let hi = vals.max() else { return 0...1 }
        let pad = max(1, (hi - lo) * 0.08)
        return (lo - pad)...(hi + pad)
    }

    /// y-range for the precip/wind chart, anchored at 0 for the filled areas.
    private var windYDomain: ClosedRange<Double> {
        var vals: [Double] = []
        for p in historic + series {
            if graphPrecip { vals.append(p.precipProbability * 100) }
            if graphGust   { vals.append(useFahrenheit ? p.windGustMPH : p.windGustKPH) }
            if graphWind   { vals.append(useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH) }
        }
        let hi = vals.max() ?? 1
        return 0...(hi + max(1, hi * 0.08))
    }

    /// Whether it's daytime *right now* — follows iOS's automatic-appearance
    /// timing by using the actual sunrise/sunset; falls back to the current
    /// hour's daylight flag when sun times aren't available (e.g. demo).
    /// Taken from whoever drew the sky; see SkyIsDayKey.
    @Environment(\.skyIsDay) private var skyIsDay
    /// Ink for axis text/legends/titles: black by day, white by night when the
    /// sky is shown; otherwise the system color (adapts to light/dark mode).
    @Environment(\.skyIsVisible) private var skyIsVisible
    /// The sky is only behind us when the user wants it *and* the screen we
    /// are on actually draws it (the table screen does not).
    private var overSky: Bool { graphSky && skyIsVisible }
    private var axisInk: Color { overSky ? (skyIsDay ? .black : .white) : .primary }
    /// Weather-series colors sit on a near-black sky at night, where they read
    /// dimmer than the same colors do on the pale daytime sky. A small lift
    /// restores the contrast. Only when the sky is actually behind them.
    private var seriesBrightness: Double { overSky && !skyIsDay ? 0.14 : 0 }
    /// x-position of "now", for the current-time marker line.
    private var nowLineDate: Date? { current?.date ?? series.first?.date }

    // MARK: Scrubbing (long-press to read a specific hour's values)
    // Two modes so swiping/scrolling keeps working — see HereTodayView for the
    // rationale. Long press drops the line at "now"; a drag layer (added only
    // while scrubbing) then moves it on any touch; ✕ on the readout dismisses.

    /// The forecast hour nearest the scrubbed time, if any.
    private var scrubPoint: ForecastPoint? {
        guard let t = scrubDate else { return nil }
        return allPoints.min { abs($0.date.timeIntervalSince(t)) < abs($1.date.timeIntervalSince(t)) }
    }

    /// Always present: a UIKit long-press drops the scrub line exactly where the
    /// finger is (and moves it while holding + dragging), and records the plot's
    /// global x-range so presses in the gaps between panels map too.
    @ViewBuilder
    private func scrubEntry(_ proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            let plot = proxy.plotFrame.map { geo[$0] }
            LongPressLocator(onTap: { scrubDate = nil }) { loc, state in
                guard plot != nil else { return }
                if state == .began || state == .changed {
                    updateScrub(atX: loc.x, proxy: proxy, geo: geo)
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

    /// A background layer so a long press *between* panels also scrubs.
    private var scrubGapEntry: some View {
        LongPressLocator(inWindow: true) { loc, state in
            guard state == .began || state == .changed,
                  let r = plotXRange, r.upperBound > r.lowerBound, let dom = dateDomain else { return }
            let frac = min(1, max(0, (loc.x - r.lowerBound) / (r.upperBound - r.lowerBound)))
            let t = dom.lowerBound.addingTimeInterval(Double(frac) * dom.upperBound.timeIntervalSince(dom.lowerBound))
            scrubDate = allPoints.min { abs($0.date.timeIntervalSince(t)) < abs($1.date.timeIntervalSince(t)) }?.date
        }
    }

    /// Active only while scrubbing: any touch/drag moves the line to that x.
    @ViewBuilder
    private func scrubDragLayer(_ proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle().fill(Color.clear).contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { updateScrub(atX: $0.location.x, proxy: proxy, geo: geo) }
                )
        }
    }

    private func updateScrub(atX xLocation: CGFloat, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let x = xLocation - geo[plotFrame].origin.x
        guard let date = proxy.value(atX: x, as: Date.self) else { return }
        scrubDate = allPoints.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }?.date
    }

    /// Where the line sits across the domain (0 = far left, 1 = far right), so
    /// the readout can sit on the opposite side and keep the line area visible.
    private var scrubFraction: Double {
        guard let t = scrubDate, let dom = dateDomain else { return 0.5 }
        let total = dom.upperBound.timeIntervalSince(dom.lowerBound)
        guard total > 0 else { return 0.5 }
        return min(1, max(0, t.timeIntervalSince(dom.lowerBound) / total))
    }

    /// A dashed vertical rule at the scrubbed time (spans both charts).
    @ChartContentBuilder
    private func scrubRule() -> some ChartContent {
        if let t = scrubDate {
            RuleMark(x: .value("Scrub", t))
                .foregroundStyle(axisInk.opacity(0.85))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
        }
    }

    private func scrubDayTimeLabel(for date: Date) -> String {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let day = TenDayView.dayFormatter.string(from: date)   // "Mon"…"Sun"
        let hh: String
        if use12Hour {
            if h == 0 { hh = "12 am" } else if h == 12 { hh = "noon" }
            else { hh = h < 12 ? "\(h) am" : "\(h - 12) pm" }
        } else {
            hh = String(format: "%02d:00", h)
        }
        return "\(day) \(hh)"
    }

    /// Compact "table row" for one hour, shown as a HUD over the temp chart.
    private func scrubReadout(_ p: ForecastPoint) -> some View {
        let unit = useFahrenheit ? "°F" : "°C"
        let windUnit = useFahrenheit ? "mph" : "kph"
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(scrubDayTimeLabel(for: p.date)).font(.subheadline.weight(.semibold))
                if let s = p.myFeelsLikeScore {
                    let clamped = max(ColorScale.minScore, min(ColorScale.maxScore, s))
                    Text(String(format: "%.0f", clamped))
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(ColorScale.contrastingText(forScore: clamped))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(ColorScale.color(forScore: clamped),
                                    in: RoundedRectangle(cornerRadius: 3))
                }
                Spacer(minLength: 10)
                Button { scrubDate = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            readoutRow("Temp/feels \(unit)", ScrubFormat.pair(
                useFahrenheit ? p.temperatureF : p.temperatureC,
                useFahrenheit ? p.apparentTemperatureF : p.apparentTemperatureC), .green)
            readoutRow("Wet bulb \(unit)",
                       String(format: "%.1f", useFahrenheit ? p.wetBulbF : p.wetBulbC), .blue)
            readoutRow("Dew pt \(unit)",
                       String(format: "%.1f", useFahrenheit ? p.dewPointF : p.dewPointC), .red)
            readoutRow("Wind \(windUnit)",
                       String(format: "%.0f", useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH), .red)
            readoutRow("Gust \(windUnit)",
                       String(format: "%.0f", useFahrenheit ? p.windGustMPH : p.windGustKPH), .red)
            readoutRow("Precip mm", String(format: "%.1f", p.precipitationMM), .blue)
            readoutRow("Precip %", String(format: "%.0f", p.precipProbability * 100), .blue)
            readoutRow("UV", String(format: "%.0f", p.uvIndex), .orange)
            readoutRow("Cloud %", String(format: "%.0f", p.cloudCover * 100), .secondary)
            readoutRow("  low/mid/high", ScrubFormat.cloudParts(p), .secondary)
        }
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

    private var earliestDate: Date? {
        historic.first?.date ?? current?.date ?? series.first?.date
    }

    private var dateDomain: ClosedRange<Date>? {
        if let r = visibleRange { return r }
        guard let lo = earliestDate, let last = series.last?.date else { return nil }
        return lo...last
    }

    private var startMidnight: Date? {
        guard let first = earliestDate else { return nil }
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: first)
        return first > midnight ? cal.date(byAdding: .day, value: 1, to: midnight) : midnight
    }

    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE"
        return df
    }()

    private static let dayAbbreviations = [
        "Mon": "Mo", "Tue": "Tu", "Wed": "We",
        "Thu": "Th", "Fri": "Fr", "Sat": "Sa", "Sun": "Su"
    ]

    /// Day tick label. Carries the day of the month, and the weekday too when
    /// the axis is wide enough for both — once the window scrolls across weeks,
    /// a bare weekday no longer says which day you are looking at.
    /// Days actually drawn across the axis. Not the same as the window: with no
    /// window the chart fits the whole series into one pane — twenty days, not
    /// ten — and taking it for ten was what let the iPad stack "Tu 1We 2Th 3"
    /// on top of itself.
    private var axisDays: Double {
        if windowStart != nil { return windowSpan / (24 * 3600) }
        guard let lo = allPoints.first?.date, let hi = allPoints.last?.date,
              hi > lo else { return 10 }
        return max(1, hi.timeIntervalSince(lo) / (24 * 3600))
    }

    /// Whole days between labelled ticks.
    private var dayTickStride: Int {
        dayAxisStride(plotWidth: plotWidth, days: axisDays)
    }

    private func dayLabel(for date: Date) -> String {
        guard let start = startMidnight, date >= start,
              Calendar.current.component(.hour, from: date) == 0 else { return "" }
        let day = Calendar.current.component(.day, from: date)
        // Judge the weekday against how many labels there will actually be,
        // which the stride has already thinned.
        let labels = axisDays / Double(max(1, dayTickStride))
        guard dayAxisFitsWeekday(plotWidth: plotWidth, days: labels) else { return "\(day)" }
        let key = TenDayView.dayFormatter.string(from: date)
        let wd = TenDayView.dayAbbreviations[key] ?? String(key.prefix(2))
        return "\(wd) \(day)"
    }

    /// Forecast point closest to "now", drawn as a ring so the current moment is
    /// obvious once the graph can scroll away from it. nil when "now" is off
    /// the visible window.
    private var nowPoint: ForecastPoint? {
        guard let p = nearestForecastPoint(to: nowTick, in: series) else { return nil }
        return abs(p.date.timeIntervalSince(nowTick)) <= 3 * 3600 ? p : nil
    }

    /// The four temperature lines (temp/wet-bulb/dew/apparent) over a set of
    /// points. `suffix` keeps the historic and forecast series distinct so they
    /// are not connected across the "now" boundary; `dash` nil = solid.
    @ChartContentBuilder
    private func tempLines(_ pts: [ForecastPoint], suffix: String, dash: [CGFloat]?) -> some ChartContent {
        // A dash means "this is the observed past" in color mode. In No color
        // mode dashes have to carry series identity instead, so the past is
        // marked by drawing it faded rather than broken.
        let isPast = dash != nil
        let fade: Double = (patternedSeries && isPast) ? 0.45 : 1
        ForEach(pts) { p in
            if graphTemp {
                LineMark(x: .value("Time", p.date),
                         y: .value("Temp", useFahrenheit ? p.temperatureF : p.temperatureC),
                         series: .value("S", "A" + suffix))
                    .foregroundStyle(seriesInk(.green).opacity(fade)).interpolationMethod(.linear)
                    .lineStyle(patternedSeries
                               ? SeriesDash.stroke(SeriesDash.dashed, patterned: true)
                               : StrokeStyle(lineWidth: seriesLineWidth, dash: dash ?? []))
            }
            if graphWetBulb {
                LineMark(x: .value("Time", p.date),
                         y: .value("Wet Bulb", useFahrenheit ? p.wetBulbF : p.wetBulbC),
                         series: .value("S", "B" + suffix))
                    .foregroundStyle(seriesInk(.blue).opacity(fade)).interpolationMethod(.linear)
                    .lineStyle(patternedSeries
                               ? SeriesDash.stroke(SeriesDash.dotted, patterned: true)
                               : StrokeStyle(lineWidth: seriesLineWidth, dash: dash ?? []))
            }
            if graphDewPoint {
                LineMark(x: .value("Time", p.date),
                         y: .value("Dew Point", useFahrenheit ? p.dewPointF : p.dewPointC),
                         series: .value("S", "C" + suffix))
                    .foregroundStyle(seriesInk(.red).opacity(fade)).interpolationMethod(.linear)
                    .lineStyle(patternedSeries
                               ? SeriesDash.stroke(SeriesDash.dashDot, patterned: true)
                               : StrokeStyle(lineWidth: seriesLineWidth, dash: dash ?? []))
            }
            if graphFeels {
                LineMark(x: .value("Time", p.date),
                         y: .value("Apparent",
                                   useFahrenheit ? p.apparentTemperatureF : p.apparentTemperatureC),
                         series: .value("S", "D" + suffix))
                    .foregroundStyle(seriesInk(.purple).opacity(fade)).interpolationMethod(.linear)
                    .lineStyle(patternedSeries
                               ? SeriesDash.stroke(SeriesDash.solid, patterned: true)
                               : StrokeStyle(lineWidth: seriesLineWidth, dash: dash ?? []))
            }
        }
    }

    /// Forecast temperature as filled bands from the axis baseline up to each
    /// curve (green = dry bulb, blue = wet bulb, red = dew point), drawn
    /// back→front with the feels-like line on top.
    @ChartContentBuilder
    private func tempAreas(_ pts: [ForecastPoint], base: Double) -> some ChartContent {
        ForEach(pts) { p in
            let dry = useFahrenheit ? p.temperatureF : p.temperatureC
            let wet = useFahrenheit ? p.wetBulbF : p.wetBulbC
            let dew = useFahrenheit ? p.dewPointF : p.dewPointC
            if graphTemp {
                AreaMark(x: .value("Time", p.date),
                         yStart: .value("base", base),
                         yEnd: .value("Temp", dry), series: .value("S", "dryA"))
                    .foregroundStyle(seriesInk(.green)).interpolationMethod(.linear)
            }
            if graphWetBulb {
                AreaMark(x: .value("Time", p.date),
                         yStart: .value("base", base),
                         yEnd: .value("Wet Bulb", wet), series: .value("S", "wetA"))
                    .foregroundStyle(seriesInk(.blue)).interpolationMethod(.linear)
            }
            if graphDewPoint {
                AreaMark(x: .value("Time", p.date),
                         yStart: .value("base", base),
                         yEnd: .value("Dew Point", dew), series: .value("S", "dewA"))
                    .foregroundStyle(seriesInk(.red)).interpolationMethod(.linear)
            }
            if graphFeels {
                LineMark(x: .value("Time", p.date),
                         y: .value("Apparent",
                                   useFahrenheit ? p.apparentTemperatureF : p.apparentTemperatureC),
                         series: .value("S", "appA"))
                    .foregroundStyle(seriesInk(.purple)).interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: seriesLineWidth))
            }
        }
    }

    /// Gust (always dashed) and wind lines over a set of points. `windDash`
    /// makes the wind line dashed for the historic pass, solid for the forecast.
    @ChartContentBuilder
    private func windLines(_ pts: [ForecastPoint], suffix: String, windDash: [CGFloat]?) -> some ChartContent {
        let isPast = windDash != nil
        let fade: Double = (patternedSeries && isPast) ? 0.45 : 1
        return ForEach(pts) { p in
            if graphGust {
                LineMark(x: .value("Time", p.date),
                         y: .value("Gust", useFahrenheit ? p.windGustMPH : p.windGustKPH),
                         series: .value("S", "G" + suffix))
                    .foregroundStyle(seriesInk(.red).opacity(patternedSeries ? fade : 0.7 * fade)).interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, dash: [4, 3]))
                    .symbol(Circle()).symbolSize(0)
            }
            if graphWind {
                LineMark(x: .value("Time", p.date),
                         y: .value("Wind", useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH),
                         series: .value("S", "W" + suffix))
                    .foregroundStyle(seriesInk(.red).opacity(fade)).interpolationMethod(.linear)
                    .lineStyle(patternedSeries
                               ? SeriesDash.stroke(SeriesDash.solid, patterned: true)
                               : StrokeStyle(lineWidth: seriesLineWidth, dash: windDash ?? []))
                    .symbol(Circle()).symbolSize(0)
            }
        }
    }

    /// Feels-like heatmap: one column per day, hour-of-day on the y-axis, cell
    /// color = personalized feels-like. Separated from the temperature curves
    /// so day-to-day and time-of-day patterns are legible (the curves' x-axis
    /// is time; this grid's y-axis is hour-of-day).
    /// What goes under the temperature chart in landscape: the in-sun map when
    /// the model has split sun from shade, otherwise whatever single thing
    /// there is to show.
    @ViewBuilder
    private func leadingComfortMap(height: CGFloat, split: Bool) -> some View {
        if split {
            let b = daylightHourBounds
            heatGrid(yLo: b.lo, yHi: b.hi,
                     yValues: [b.lo, (b.lo + b.hi) / 2, b.hi]) { p in
                guard p.isDaylight, let s = p.myFeelsLikeSunScore else { return nil }
                return AnyShapeStyle(ColorScale.feelsColor(score: s, opacity: 1))
            }
            .frame(height: height)
        } else {
            feelsLikeHeatmap(height: height)
        }
    }

    /// The in-shade map, which in landscape goes under the wind chart.
    private func shadeHeatmap(height: CGFloat) -> some View {
        heatGrid(yLo: 0, yHi: 24, yValues: [0, 6, 12, 18, 24]) { p in
            (p.myFeelsLikeShadeScore ?? p.myFeelsLikeScore).map {
                AnyShapeStyle(ColorScale.feelsColor(score: $0, opacity: 1))
            }
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func feelsLikeHeatmap(height: CGFloat) -> some View {
        if hasModel && comfortAsLineGraph {
            VStack(alignment: .leading, spacing: 2) {
                Text("MyFeelsLike")
                    .font(.caption2).foregroundStyle(axisInk)
                    .padding(.leading, 36)
                comfortLineGraph.frame(height: height - 16)
            }
        } else if hasModel && hasSunSplit {
            separateHeatmaps(height: height)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("MyFeelsLike by time of day")
                    .font(.caption2).foregroundStyle(axisInk)
                    .padding(.leading, 36)
                if hasModel {
                    heatmapChart.frame(height: height - 16)
                } else {
                    noModelPanel.frame(height: height - 16)
                }
            }
        }
    }

    /// Whether the forecast carries a distinct in-sun vs in-shade prediction
    /// (i.e. the model learned a sun effect), so the "separate" style has two
    /// things to show.
    private var hasSunSplit: Bool {
        allPoints.contains {
            guard let sun = $0.myFeelsLikeSunScore, let shade = $0.myFeelsLikeShadeScore
            else { return false }
            return sun != shade
        }
    }

    /// Daylight hour window across the forecast (min sunrise hour … max sunset
    /// hour), used to crop the night off the in-sun heatmap so it takes less
    /// room. Falls back to a sensible 6…20 if daylight can't be determined.
    private var daylightHourBounds: (lo: Int, hi: Int) {
        let hrs = allPoints.filter { $0.isDaylight }
            .map { Calendar.current.component(.hour, from: $0.date) }
        guard let lo = hrs.min(), let hi = hrs.max() else { return (6, 20) }
        return (lo, min(24, hi + 1))
    }

    /// Separate style: an in-shade heatmap over the full day, and a shorter
    /// in-sun heatmap cropped to daylight hours (no sun at night). Heights are
    /// split so both grids keep roughly the same cell size.
    @ViewBuilder
    /// One grid, each day column cut down the middle: in shade on the left of
    /// the day, in sun on the right.
    ///
    /// Stacking two grids gave the in-sun one a sliver of the height — it only
    /// covers daylight hours, so its share of the split was always small — and
    /// it read as an afterthought rather than the other half of the same
    /// reading. Side by side within the day, the two are directly comparable at
    /// a glance, hour for hour.
    private func splitHeatGrid() -> some View {
        let cal = Calendar.current
        return Chart(allPoints) { p in
            let hour = cal.component(.hour, from: p.date)
            let dayStart = cal.startOfDay(for: p.date)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            // Reliability still shrinks the pair toward the middle of the day,
            // so an uncertain hour reads as a narrow sliver either side.
            let full = dayEnd.timeIntervalSince(dayStart)
            let mid = dayStart.addingTimeInterval(full / 2)
            let half = full / 2 * myFeelsLikeReliability(p)
            if let shade = p.myFeelsLikeShadeScore ?? p.myFeelsLikeScore {
                RectangleMark(
                    xStart: .value("Day", mid.addingTimeInterval(-half)),
                    xEnd:   .value("Day end", mid),
                    yStart: .value("Hour", hour),
                    yEnd:   .value("Hour end", hour + 1)
                )
                .foregroundStyle(ColorScale.feelsColor(score: shade, opacity: 1))
            }
            if let sun = p.myFeelsLikeSunScore {
                RectangleMark(
                    xStart: .value("Day", mid),
                    xEnd:   .value("Day end", mid.addingTimeInterval(half)),
                    yStart: .value("Hour", hour),
                    yEnd:   .value("Hour end", hour + 1)
                )
                .foregroundStyle(ColorScale.feelsColor(score: sun, opacity: 1))
            }
        }
        .chartYScale(domain: 0...24)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 6, 12, 18, 24]) { v in
                let hv = v.as(Int.self) ?? 0
                AxisValueLabel {
                    Text(hv == 24 && !use12Hour ? "24" : clockHourLabel(hv, use12: use12Hour))
                        .font(.caption2).foregroundStyle(axisInk)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: dayTickStride)) { value in
                AxisValueLabel {
                    Text(value.as(Date.self).map { dayLabel(for: $0) } ?? "")
                        .font(.caption).foregroundStyle(axisInk)
                }
            }
        }
        .ifLet(dateDomain) { view, domain in view.chartXScale(domain: domain) }
        .chartPlotStyle { $0.clipped() }
    }

    private func separateHeatmaps(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MyFeelsLike — in shade (left) · in sun (right)")
                .font(.caption2).foregroundStyle(axisInk).padding(.leading, 36)
            splitHeatGrid()
                .frame(height: max(40, height - 16))
        }
    }

    /// Comfort over the ten days as a curve — the same shape as the
    /// temperature chart above it, sharing its x-axis, just a shorter panel.
    /// Unlike the heatmap this drops the hour-of-day dimension: it is one
    /// reading per hour laid along the same timeline, not a grid.
    private var comfortLineGraph: some View {
        Chart {
            ForEach(historicPlus) { p in
                if let v = p.myFeelsLikeShadeScore ?? p.myFeelsLikeScore {
                    LineMark(x: .value("Time", p.date), y: .value("Comfort", v),
                             series: .value("S", "past"))
                        .foregroundStyle(axisInk.opacity(0.45)).interpolationMethod(.linear)
                        .lineStyle(SeriesDash.stroke(SeriesDash.solid, patterned: true))
                }
            }
            ForEach(forecastPlus) { p in
                if let v = p.myFeelsLikeShadeScore ?? p.myFeelsLikeScore {
                    LineMark(x: .value("Time", p.date), y: .value("Comfort", v),
                             series: .value("S", "shade"))
                        .foregroundStyle(axisInk).interpolationMethod(.linear)
                        .lineStyle(SeriesDash.stroke(SeriesDash.solid, patterned: true))
                }
                if hasSunSplit, let v = p.myFeelsLikeSunScore {
                    LineMark(x: .value("Time", p.date), y: .value("In sun", v),
                             series: .value("S", "sun"))
                        .foregroundStyle(axisInk).interpolationMethod(.linear)
                        .lineStyle(SeriesDash.stroke(SeriesDash.dashed, patterned: true))
                }
            }
        }
        .chartYScale(domain: ColorScale.minScore...ColorScale.maxScore)
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
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                AxisGridLine().foregroundStyle(.gray.opacity(0.25))
            }
        }
        .ifLet(dateDomain) { view, domain in view.chartXScale(domain: domain) }
        .chartPlotStyle { $0.clipped() }
    }

    private var heatmapChart: some View {
        heatGrid(yLo: 0, yHi: 24, yValues: [0, 6, 12, 18, 24]) { cellStyle($0) }
    }

    /// One day-column heatmap: `color` fills each (day, hour) cell, returning nil
    /// to leave a cell blank (used to drop night from the in-sun grid). The
    /// y-axis spans `yLo…yHi` hours; cell width still shrinks with reliability.
    private func heatGrid(yLo: Int, yHi: Int, yValues: [Int],
                          color: @escaping (ForecastPoint) -> AnyShapeStyle?) -> some View {
        let cal = Calendar.current
        return Chart(allPoints) { p in
            let hour = cal.component(.hour, from: p.date)
            if hour >= yLo, hour < yHi, let style = color(p) {
                let dayStart = cal.startOfDay(for: p.date)
                let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
                // Reliability shrinks the cell horizontally toward the center of
                // its day column, so uncertain hours read as a narrow sliver.
                let full = dayEnd.timeIntervalSince(dayStart)
                let mid = dayStart.addingTimeInterval(full / 2)
                let half = full / 2 * myFeelsLikeReliability(p)
                RectangleMark(
                    xStart: .value("Day", mid.addingTimeInterval(-half)),
                    xEnd:   .value("Day end", mid.addingTimeInterval(half)),
                    yStart: .value("Hour", hour),
                    yEnd:   .value("Hour end", hour + 1)
                )
                .foregroundStyle(style)
            }
        }
        .chartYScale(domain: yLo...yHi)
        .chartYAxis {
            AxisMarks(position: .leading, values: yValues) { v in
                let hv = v.as(Int.self) ?? 0
                AxisValueLabel {
                    Text(hv == 24 && !use12Hour ? "24" : clockHourLabel(hv, use12: use12Hour))
                        .font(.caption2).foregroundStyle(axisInk)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: dayTickStride)) { value in
                AxisValueLabel {
                    Text(value.as(Date.self).map { dayLabel(for: $0) } ?? "")
                        .font(.caption).foregroundStyle(axisInk)
                }
            }
        }
        // Share the temperature chart's window. Without this the grid derived
        // its own domain from the data, which lined up only while every chart
        // covered the same range — once the charts became scrollable the
        // heatmap drifted out of step with the curves above it.
        .ifLet(dateDomain) { view, domain in view.chartXScale(domain: domain) }
        .chartPlotStyle { $0.clipped() }
    }

    /// Fill for one heatmap cell. The sun/shade split is drawn as two grids
    /// (see separateHeatmaps), so a single cell is always one solid color.
    private func cellStyle(_ p: ForecastPoint) -> AnyShapeStyle {
        AnyShapeStyle(myFeelsLikeHeatColor(p))
    }

    /// Gray panel shown in place of the heatmap until a personalized model
    /// exists, explaining why (with quantities where possible).
    private var noModelPanel: some View {
        ZStack {
            // A frosted material (not translucent gray) so the text keeps
            // contrast over the weather-sky background, day or night.
            RoundedRectangle(cornerRadius: 8).fill(.regularMaterial)
            VStack(alignment: .leading, spacing: 6) {
                Text("No personalized feels-like color yet")
                    .font(.caption.weight(.semibold))
                if modelReasons.isEmpty {
                    Text("Building your model…")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    ForEach(modelReasons, id: \.self) { reason in
                        Text("• " + reason)
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }


    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            // Deliberately not a ScrollView: the content is sized to the screen,
            // and a scroll view would swallow the vertical drag that now
            // switches screens. Refresh moved to the header bar with it.
            Group {
                if series.isEmpty {
                    ForecastLoadingView(progress: progress, nowTick: nowTick, errorMessage: errorMessage)
                        .padding()
                        .frame(minHeight: h)
                } else if verticalSizeClass == .compact || forceLandscapeLayout {
                    // Landscape: the charts side by side, each with the comfort
                    // map that belongs to it underneath, sharing its days.
                    // Three panels abreast left each one too narrow to read.
                    let split = hasModel && hasSunSplit && !comfortAsLineGraph
                    let chartH = colorPanelVisible ? h * 0.58 : h * 0.9
                    let mapH = max(40, h * 0.28)
                    VStack(spacing: 6) {
                        ScenarioStrip(activeFeatures: activeFeatures)
                        HStack(spacing: 12) {
                            if tempPanelVisible {
                                VStack(spacing: 2) {
                                    temperatureChart(height: chartH)
                                    if colorPanelVisible { leadingComfortMap(height: mapH, split: split) }
                                }
                            }
                            if windPanelVisible {
                                VStack(spacing: 2) {
                                    precipWindChart(height: chartH)
                                    if colorPanelVisible && split { shadeHeatmap(height: mapH) }
                                }
                            }
                        }
                        if let attribution {
                            WeatherAttributionLink(info: attribution)
                        }
                    }
                    .padding(.horizontal)
                    .frame(minHeight: h)
                } else {
                    let hh = panelHeights(h)
                    VStack(spacing: 8) {
                        ScenarioStrip(activeFeatures: activeFeatures)
                        if tempPanelVisible { temperatureChart(height: hh.temp) }
                        if colorPanelVisible { feelsLikeHeatmap(height: hh.color) }
                        if windPanelVisible { precipWindChart(height: hh.wind) }
                        if let attribution {
                            WeatherAttributionLink(info: attribution)
                        }
                    }
                    .padding(.horizontal)
                    .frame(minHeight: h)
                    // A long press between panels scrubs too.
                    .background(scrubGapEntry)
                }
            }
            .onAppear { plotWidth = geo.size.width }
            .onChange(of: geo.size.width) { _, w in plotWidth = w }
        }
    }

    @ViewBuilder
    private func temperatureChart(height: CGFloat) -> some View {
        // Compute the domain once (O(n)) — reading it inside a per-point
        // ForEach would make it O(n²) and stall scrolling/swiping.
        let dom = tempYDomain
        VStack(alignment: .leading, spacing: 2) {
            // Legend without units — only for the enabled series.
            ChartLegendRow(entries: tempLegendEntries, dashes: tempLegendDashes, ink: axisInk)
                .saturation(visionMode == .noColor ? 0 : graphPalette.saturation)
            .padding(.leading, 36)

            Chart {
                // Area mode: past, current and forecast share the same filled
                // bands. Lines mode: dashed past + solid forecast curves (a
                // classic meteogram), joined at "now".
                if linesOnly {
                    tempLines(historicPlus, suffix: "h", dash: [4, 3])
                    tempLines(forecastPlus, suffix: "",  dash: nil)
                } else {
                    tempAreas(allPoints, base: dom.lowerBound)
                }
                if let nx = nowLineDate {
                    RuleMark(x: .value("Now", nx))
                        .foregroundStyle(axisInk.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                scrubRule()
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in scrubEntry(proxy) }
            .chartOverlay { proxy in if scrubDate != nil { scrubDragLayer(proxy) } }
            .chartYScale(domain: dom)
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 5)) { _ in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel().font(.caption).foregroundStyle(axisInk)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: dayTickStride)) { value in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel {
                        Text(value.as(Date.self).map { dayLabel(for: $0) } ?? "")
                            .font(.caption).foregroundStyle(axisInk)
                    }
                }
            }
            .ifLet(dateDomain) { view, domain in view.chartXScale(domain: domain) }
            .chartPlotStyle { $0.clipped() }
            // Unit annotation just below the topmost y-axis number.
            .overlay(alignment: .topLeading) {
                Text(useFahrenheit ? "°F" : "°C")
                    .font(.caption2)
                    .foregroundStyle(axisInk)
                    .padding(.leading, 4)
                    .padding(.top, 14)
            }
            // Scrub readout HUD — sits opposite the line so the line area stays
            // visible; ✕ on the card dismisses.
            .overlay(alignment: scrubFraction < 0.5 ? .topTrailing : .topLeading) {
                if let p = scrubPoint {
                    scrubReadout(p)
                        .padding(.top, 6)
                        .padding(.horizontal, 6)
                        .transition(.opacity)
                }
            }
            .frame(height: height - 20)
        }
        .saturation(visionMode == .noColor ? 0 : graphPalette.saturation)
            .brightness(seriesBrightness)
    }

    @ViewBuilder
    private func precipWindChart(height: CGFloat) -> some View {
        // Compute the domain once (O(n)); reading it per-point would be O(n²).
        let dom = windYDomain
        let base = dom.lowerBound
        let windPts = historic + series
        VStack(alignment: .leading, spacing: 2) {
            Chart {
                // Areas back→front over history + forecast: gust (translucent
                // red) → wind (solid red) → rain (solid blue). The gust and
                // wind curves are drawn on top of the rain so they stay readable.
                ForEach(windPts) { p in
                    let gust = useFahrenheit ? p.windGustMPH : p.windGustKPH
                    let wind = useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH
                    if graphGust && !linesOnly {
                        AreaMark(x: .value("Time", p.date),
                                 yStart: .value("base", base),
                                 yEnd: .value("Gust", gust), series: .value("S", "gustA"))
                            .foregroundStyle(seriesInk(.red).opacity(0.35)).interpolationMethod(.linear)
                    }
                    if graphWind && !linesOnly {
                        AreaMark(x: .value("Time", p.date),
                                 yStart: .value("base", base),
                                 yEnd: .value("Wind", wind), series: .value("S", "windA"))
                            .foregroundStyle(seriesInk(.red)).interpolationMethod(.linear)
                    }
                    if graphPrecip {
                        if linesOnly {
                            LineMark(x: .value("Time", p.date),
                                     y: .value("Precip %", p.precipProbability * 100),
                                     series: .value("S", "rainL"))
                                .foregroundStyle(seriesInk(.blue)).interpolationMethod(.linear)
                                .lineStyle(StrokeStyle(lineWidth: seriesLineWidth))
                        } else {
                            AreaMark(x: .value("Time", p.date),
                                     yStart: .value("base", base),
                                     yEnd: .value("Precip %", p.precipProbability * 100), series: .value("S", "rainA"))
                                .foregroundStyle(seriesInk(.blue)).interpolationMethod(.linear)
                        }
                    }
                }
                // Wind/gust curves: dashed past, solid future, joined at "now".
                windLines(historicPlus, suffix: "h", windDash: [4, 3])
                windLines(forecastPlus, suffix: "",  windDash: nil)
                if let nx = nowLineDate {
                    RuleMark(x: .value("Now", nx))
                        .foregroundStyle(axisInk.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                scrubRule()
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in scrubEntry(proxy) }
            .chartOverlay { proxy in if scrubDate != nil { scrubDragLayer(proxy) } }
            // Area mode flips the scale — zero at the top (nearest the heatmap),
            // so the wind/rain areas hang downward and share the day labels
            // above. Lines mode reads the normal way up (zero at the bottom).
            .chartYScale(domain: linesOnly ? [dom.lowerBound, dom.upperBound]
                                            : [dom.upperBound, dom.lowerBound])
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel().font(.caption).foregroundStyle(axisInk)
                }
            }
            .chartXAxis {
                // Grid lines only — day labels are shared with the chart above.
                AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                }
            }
            .ifLet(dateDomain) { view, domain in view.chartXScale(domain: domain) }
            .chartPlotStyle { $0.clipped() }
            .frame(height: height - 20)

            // Legend below the panel (moved from the top), near the largest values.
            ChartLegendRow(entries: windLegendEntries, dashes: windLegendDashes, ink: axisInk)
                .padding(.leading, 36)
        }
        .saturation(visionMode == .noColor ? 0 : graphPalette.saturation)
            .brightness(seriesBrightness)
    }
}
