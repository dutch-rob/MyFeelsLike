// SPDX-License-Identifier: GPL-3.0-or-later
//
//  HereTodayView.swift
//  MyFeelsLike
//
//  The 24-hour screen: the temperature band chart, the MyFeelsLike color band
//  (single, or split into in-sun / in-shade), and the precip/wind chart.
//

import SwiftUI
import Charts

// MARK: - HereTodayView

struct HereTodayView: View {
    var series: [ForecastPoint]
    /// Apple's current-conditions nowcast, drawn as prominent "now" dots in a
    /// small gap to the left of the forecast curves.
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
    /// When true (the model learned a sun effect), the MyFeelsLike color band
    /// splits into an in-sun (top) and in-shade (bottom) half.
    var sunFeatureActive: Bool = false
    /// True when embedded in a fixed-height dashboard pane (iPad): panel
    /// fractions shrink so everything fits without scrolling.
    var fitsPane: Bool = false

    @AppStorage(SettingsKey.useFahrenheit) private var useFahrenheit: Bool = true
    @AppStorage(SettingsKey.use12HourClock) private var use12Hour = false
    @AppStorage(GraphKey.temp)     private var graphTemp     = true
    @AppStorage(GraphKey.wetBulb)  private var graphWetBulb  = true
    @AppStorage(GraphKey.dewPoint) private var graphDewPoint = true
    @AppStorage(GraphKey.feels)    private var graphFeels    = true
    @AppStorage(GraphKey.color)   private var graphColor   = true
    @AppStorage(GraphKey.precip)   private var graphPrecip   = true
    @AppStorage(GraphKey.wind)     private var graphWind     = true
    @AppStorage(GraphKey.gust)     private var graphGust     = true
    @AppStorage(GraphKey.sky)      private var graphSky      = true
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var tempPanelVisible: Bool { graphTemp || graphWetBulb || graphDewPoint || graphFeels }
    private var colorPanelVisible: Bool { graphColor }
    private var windPanelVisible: Bool { graphPrecip || graphWind || graphGust }

    private var tempLegendEntries: [(color: Color, label: String, isArea: Bool)] {
        var e: [(color: Color, label: String, isArea: Bool)] = []
        if graphFeels    { e.append((.purple, "Feels like", false)) }
        if graphTemp     { e.append((.green,  "Temp",        false)) }
        if graphWetBulb  { e.append((.blue,   "Wet Bulb",    false)) }
        if graphDewPoint { e.append((.red,    "Dew Pt",      false)) }
        return e
    }

    private var windLegendEntries: [(color: Color, label: String, isArea: Bool)] {
        var e: [(color: Color, label: String, isArea: Bool)] = []
        if graphPrecip { e.append((.blue, "Precip %", true)) }
        if graphWind   { e.append((.red,  useFahrenheit ? "Wind mph" : "Wind kph", false)) }
        if graphGust   { e.append((.red.opacity(0.5), useFahrenheit ? "Gust mph" : "Gust kph", false)) }
        return e
    }

    /// Normalised panel heights over whichever panels are enabled. The color
    /// band is deliberately thin; `usable` < 1 leaves room for the panel
    /// labels + scenario strip + attribution so everything fits without
    /// scrolling.
    private func panelHeights(_ h: CGFloat) -> (temp: CGFloat, color: CGFloat, wind: CGFloat) {
        let wT = tempPanelVisible ? 0.50 : 0
        let wC = colorPanelVisible ? 0.08 : 0
        let wW = windPanelVisible ? 0.36 : 0
        let tot = wT + wC + wW
        guard tot > 0 else { return (0, 0, 0) }
        let usable = h * (fitsPane ? 0.90 : 0.84)
        return (usable * wT / tot, usable * wC / tot, usable * wW / tot)
    }

    /// Domain begins ~1 h before "now" so the forecast curves sit slightly to
    /// the right, leaving a gap on the left for the prominent current dots.
    private var dateDomain: ClosedRange<Date>? {
        guard let last = series.last?.date else { return nil }
        let lo: Date
        if let c = current?.date {
            lo = c.addingTimeInterval(-3600)
        } else if let first = series.first?.date {
            lo = first
        } else {
            return nil
        }
        return lo...last
    }

    private func hourLabel(for date: Date) -> String {
        clockHourLabel(Calendar.current.component(.hour, from: date), use12: use12Hour)
    }

    /// Whether the forecast carries personalized feels-like scores.
    private var hasModel: Bool {
        series.contains { $0.myFeelsLikeScore != nil }
    }

    /// Tight y-range covering the four temperature curves (+ the current dots),
    /// used as the explicit scale so the filled bands have a defined baseline.
    private var tempYDomain: ClosedRange<Double> {
        var vals: [Double] = []
        for p in series + (current.map { [$0] } ?? []) {
            if graphTemp     { vals.append(useFahrenheit ? p.temperatureF : p.temperatureC) }
            if graphWetBulb  { vals.append(useFahrenheit ? p.wetBulbF : p.wetBulbC) }
            if graphDewPoint { vals.append(useFahrenheit ? p.dewPointF : p.dewPointC) }
            if graphFeels    { vals.append(useFahrenheit ? p.apparentTemperatureF : p.apparentTemperatureC) }
        }
        guard let lo = vals.min(), let hi = vals.max() else { return 0...1 }
        let pad = max(1, (hi - lo) * 0.08)
        return (lo - pad)...(hi + pad)
    }

    /// y-range for the precip/wind chart, always anchored at 0 so the filled
    /// areas have a sensible baseline.
    private var windYDomain: ClosedRange<Double> {
        var vals: [Double] = []
        for p in series + (current.map { [$0] } ?? []) {
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
    private var skyIsDay: Bool {
        if let sr = sunrise, let ss = sunset { return nowTick >= sr && nowTick < ss }
        return (series.first ?? current)?.isDaylight ?? true
    }
    /// Ink for axis text/legends/titles: black by day, white by night when the
    /// sky is shown; otherwise the system color (adapts to light/dark mode).
    private var axisInk: Color { graphSky ? (skyIsDay ? .black : .white) : .primary }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ScrollView {
                if series.isEmpty {
                    ForecastLoadingView(progress: progress, nowTick: nowTick, errorMessage: errorMessage)
                        .padding()
                        .frame(minHeight: h)
                } else if verticalSizeClass == .compact {
                    // iPhone landscape: an optional thin MyFeelsLike strip on
                    // top, the enabled charts side by side below it.
                    VStack(spacing: 8) {
                        ScenarioStrip(activeFeatures: activeFeatures)
                        if colorPanelVisible { myFeelsLikePanel(height: h * 0.16) }
                        HStack(spacing: 12) {
                            if tempPanelVisible { temperatureChart(height: colorPanelVisible ? h * 0.72 : h * 0.9) }
                            if windPanelVisible { precipWindChart(height: colorPanelVisible ? h * 0.72 : h * 0.9) }
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
                        if colorPanelVisible { myFeelsLikePanel(height: hh.color) }
                        if windPanelVisible { precipWindChart(height: hh.wind) }
                        if let attribution {
                            WeatherAttributionLink(info: attribution)
                        }
                    }
                    .padding(.horizontal)
                    .frame(minHeight: h)
                }
            }
            .refreshable { await onRefresh?() }
        }
    }

    /// A thin horizontal MyFeelsLike color band across the 24 hours — the 24h
    /// analogue of the 10-day heatmap, but a single row (narrower). Aligned in
    /// time with the temperature chart's plot area via the leading padding.
    /// When the model has learned a sun effect it splits into two half-height
    /// rows: in-sun on top, in-shade below.
    @ViewBuilder
    private func myFeelsLikePanel(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sunFeatureActive && hasModel ? "MyFeelsLike — sun / shade" : "MyFeelsLike by hour")
                .font(.caption2).foregroundStyle(axisInk)
                .padding(.leading, 36)
            if hasModel {
                if sunFeatureActive { splitColorBand(height: height) }
                else { singleColorBand(height: height) }
            } else {
                // Frosted material keeps the text legible over the sky background.
                RoundedRectangle(cornerRadius: 6).fill(.regularMaterial)
                    .frame(height: height)
                    .padding(.leading, 36)
                    .overlay(
                        Text("No personalized color yet")
                            .font(.caption2).foregroundStyle(.primary)
                    )
            }
        }
    }

    /// Single-row color band (current scenario), reliability as thickness.
    private func singleColorBand(height: CGFloat) -> some View {
        Chart(series) { p in
            // Reliability shrinks the band vertically toward the center line, so
            // uncertain hours read as a thinner stripe.
            let half = myFeelsLikeReliability(p) / 2
            // Cell spans the hour *ending* at p.date (shifted ~1h left of the
            // hour-starting convention) so the band lines up with how the
            // temperature curve reads against the x-axis ticks.
            RectangleMark(
                xStart: .value("t0", p.date.addingTimeInterval(-3600)),
                xEnd:   .value("t1", p.date),
                yStart: .value("y0", 0.5 - half),
                yEnd:   .value("y1", 0.5 + half)
            )
            .foregroundStyle(myFeelsLikeHeatColor(p))
        }
        .chartYScale(domain: 0...1)
        // Reserve the same leading width as the temperature/wind charts (a clear
        // 2-digit y-axis) so the band lines up with them.
        .chartYAxis {
            AxisMarks(position: .leading, values: [0]) {
                AxisValueLabel { Text("00").font(.caption).foregroundStyle(.clear) }
            }
        }
        .chartXAxis(.hidden)
        .ifLet(dateDomain) { view, domain in view.chartXScale(domain: domain) }
        .frame(height: height)
    }

    /// Gradient band: each hour cell runs in-shade (left) → in-sun (right), so a
    /// column's shade↔sun spread reads horizontally. Reliability shrinks the cell
    /// vertically, matching the single band. Night cells (sun == shade) fall back
    /// to the solid MyFeelsLike color.
    private func splitColorBand(height: CGFloat) -> some View {
        Chart {
            ForEach(series) { p in
                let x0 = p.date.addingTimeInterval(-3600)   // hour ending at p.date
                let half = myFeelsLikeReliability(p) / 2
                let style: AnyShapeStyle = sunShadeGradient(p).map(AnyShapeStyle.init)
                    ?? AnyShapeStyle(bandColor(p.myFeelsLikeScore, opacity: p.myFeelsLikeOpacity))
                RectangleMark(xStart: .value("t0", x0), xEnd: .value("t1", p.date),
                              yStart: .value("y0", 0.5 - half), yEnd: .value("y1", 0.5 + half))
                    .foregroundStyle(style)
            }
        }
        .chartYScale(domain: 0...1)
        // Reserve the same leading width as the temperature/wind charts so the
        // band lines up with them.
        .chartYAxis {
            AxisMarks(position: .leading, values: [0]) {
                AxisValueLabel { Text("00").font(.caption).foregroundStyle(.clear) }
            }
        }
        .chartXAxis(.hidden)
        .ifLet(dateDomain) { view, domain in view.chartXScale(domain: domain) }
        .frame(height: height)
    }

    /// Color for a split-band cell: the score's color, opacity carrying
    /// prediction reliability. Gray when there's no score.
    private func bandColor(_ score: Double?, opacity: Double) -> Color {
        ColorScale.feelsColor(score: score, opacity: opacity, floor: 0.2)
    }

    @ViewBuilder
    private func temperatureChart(height: CGFloat) -> some View {
        // Compute the domain once (O(n)); reading it per-point would be O(n²).
        let dom = tempYDomain
        let base = dom.lowerBound
        VStack(alignment: .leading, spacing: 2) {
            // Legend without units — only for the enabled series.
            ChartLegendRow(entries: tempLegendEntries, ink: axisInk)
            .padding(.leading, 36)   // start near the y-axis line, not the y-axis labels

            Chart {
                ForEach(series) { p in
                    let dry = useFahrenheit ? p.temperatureF : p.temperatureC
                    let wet = useFahrenheit ? p.wetBulbF : p.wetBulbC
                    let dew = useFahrenheit ? p.dewPointF : p.dewPointC
                    // Each band fills from the axis baseline up to its own curve,
                    // drawn back→front (dry → wet → dew). Since dry ≥ wet ≥ dew,
                    // the opaque fronts nest into clean bands — and any band still
                    // reaches the axis when the ones below it are turned off.
                    if graphTemp {
                        AreaMark(x: .value("Time", p.date),
                                 yStart: .value("base", base),
                                 yEnd: .value("Temp", dry),
                                 series: .value("S", "dry"))
                            .foregroundStyle(.green).interpolationMethod(.linear)
                    }
                    if graphWetBulb {
                        AreaMark(x: .value("Time", p.date),
                                 yStart: .value("base", base),
                                 yEnd: .value("Wet Bulb", wet),
                                 series: .value("S", "wet"))
                            .foregroundStyle(.blue).interpolationMethod(.linear)
                    }
                    if graphDewPoint {
                        AreaMark(x: .value("Time", p.date),
                                 yStart: .value("base", base),
                                 yEnd: .value("Dew Point", dew),
                                 series: .value("S", "dew"))
                            .foregroundStyle(.red).interpolationMethod(.linear)
                    }
                    // Personalized feels-like (apparent) stays a line, on top.
                    if graphFeels {
                        LineMark(x: .value("Time", p.date),
                                 y: .value("Apparent",
                                           useFahrenheit ? p.apparentTemperatureF : p.apparentTemperatureC),
                                 series: .value("S", "app"))
                            .foregroundStyle(.purple).interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
                // Prominent "now" dots in the gap left of the forecast curves.
                if let c = current {
                    if graphTemp {
                        PointMark(x: .value("Time", c.date),
                                  y: .value("Temp", useFahrenheit ? c.temperatureF : c.temperatureC))
                            .foregroundStyle(.green).symbolSize(110)
                    }
                    if graphWetBulb {
                        PointMark(x: .value("Time", c.date),
                                  y: .value("Wet Bulb", useFahrenheit ? c.wetBulbF : c.wetBulbC))
                            .foregroundStyle(.blue).symbolSize(110)
                    }
                    if graphDewPoint {
                        PointMark(x: .value("Time", c.date),
                                  y: .value("Dew Point", useFahrenheit ? c.dewPointF : c.dewPointC))
                            .foregroundStyle(.red).symbolSize(110)
                    }
                    if graphFeels {
                        PointMark(x: .value("Time", c.date),
                                  y: .value("Apparent",
                                            useFahrenheit ? c.apparentTemperatureF : c.apparentTemperatureC))
                            .foregroundStyle(.purple).symbolSize(110)
                    }
                }
            }
            // MyFeelsLike color now lives in its own panel below (see
            // myFeelsLikePanel), matching the 10-day screen's heatmap.
            .chartLegend(.hidden)
            .chartYScale(domain: dom)
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 5)) { _ in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel().font(.caption).foregroundStyle(axisInk)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel(centered: true) {
                        Text(value.as(Date.self).map { hourLabel(for: $0) } ?? "")
                            .font(.caption).foregroundStyle(axisInk)
                    }
                }
            }
            .ifLet(dateDomain) { view, domain in view.chartXScale(domain: domain) }
            // Unit annotation just below the topmost y-axis number, in-plot
            // (so the chart area does not need to shrink to make room).
            .overlay(alignment: .topLeading) {
                Text(useFahrenheit ? "°F" : "°C")
                    .font(.caption2)
                    .foregroundStyle(axisInk)
                    .padding(.leading, 4)
                    .padding(.top, 14)
            }
            .frame(height: height - 20)
        }
    }

    @ViewBuilder
    private func precipWindChart(height: CGFloat) -> some View {
        // Compute the domain once (O(n)); reading it per-point would be O(n²).
        let dom = windYDomain
        let base = dom.lowerBound
        VStack(alignment: .leading, spacing: 2) {
            ChartLegendRow(entries: windLegendEntries, ink: axisInk)
            .padding(.leading, 36)

            Chart {
                ForEach(series) { p in
                    let gust = useFahrenheit ? p.windGustMPH : p.windGustKPH
                    let wind = useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH
                    // Areas back→front: gust (translucent red) → wind (solid
                    // red) → rain (solid blue). The gust and wind curves are
                    // then drawn on top of the rain so they stay readable.
                    if graphGust {
                        AreaMark(x: .value("Time", p.date),
                                 yStart: .value("base", base),
                                 yEnd: .value("Gust", gust), series: .value("S", "gustA"))
                            .foregroundStyle(.red.opacity(0.35)).interpolationMethod(.linear)
                    }
                    if graphWind {
                        AreaMark(x: .value("Time", p.date),
                                 yStart: .value("base", base),
                                 yEnd: .value("Wind", wind), series: .value("S", "windA"))
                            .foregroundStyle(.red).interpolationMethod(.linear)
                    }
                    if graphPrecip {
                        AreaMark(x: .value("Time", p.date),
                                 yStart: .value("base", base),
                                 yEnd: .value("Precip %", p.precipProbability * 100), series: .value("S", "rainA"))
                            .foregroundStyle(.blue).interpolationMethod(.linear)
                    }
                    // Gust dashed + wind solid lines, on top of the areas.
                    if graphGust {
                        LineMark(x: .value("Time", p.date),
                                 y: .value("Gust", gust), series: .value("S", "gustL"))
                            .foregroundStyle(.red.opacity(0.7)).interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 2.4, dash: [4, 3]))
                            .symbol(Circle()).symbolSize(0)
                    }
                    if graphWind {
                        LineMark(x: .value("Time", p.date),
                                 y: .value("Wind", wind), series: .value("S", "windL"))
                            .foregroundStyle(.red).interpolationMethod(.linear)
                            .symbol(Circle()).symbolSize(0)
                    }
                }
                // Prominent "now" wind/gust dots (current has no precipitation).
                if let c = current {
                    if graphGust {
                        PointMark(x: .value("Time", c.date),
                                  y: .value("Gust", useFahrenheit ? c.windGustMPH : c.windGustKPH))
                            .foregroundStyle(.red.opacity(0.45)).symbolSize(90)
                    }
                    if graphWind {
                        PointMark(x: .value("Time", c.date),
                                  y: .value("Wind", useFahrenheit ? c.windSpeedMPH : c.windSpeedKPH))
                            .foregroundStyle(.red).symbolSize(90)
                    }
                }
            }
            .chartLegend(.hidden)
            .chartYScale(domain: dom)
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 5)) { _ in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel().font(.caption).foregroundStyle(axisInk)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel(centered: true) {
                        Text(value.as(Date.self).map { hourLabel(for: $0) } ?? "")
                            .font(.caption).foregroundStyle(axisInk)
                    }
                }
            }
            .ifLet(dateDomain) { view, domain in view.chartXScale(domain: domain) }
            .frame(height: height - 20)
        }
    }
}
