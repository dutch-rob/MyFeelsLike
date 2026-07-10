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

    private func panelHeights(_ h: CGFloat) -> (temp: CGFloat, color: CGFloat, wind: CGFloat) {
        let wT = tempPanelVisible ? 0.42 : 0
        let wC = colorPanelVisible ? 0.30 : 0
        let wW = windPanelVisible ? 0.32 : 0
        let tot = wT + wC + wW
        guard tot > 0 else { return (0, 0, 0) }
        // usable < 1 leaves room for the three panel labels + scenario strip +
        // attribution so the bottom panel's x-axis isn't clipped.
        let usable = h * (fitsPane ? 0.90 : 0.82)
        return (usable * wT / tot, usable * wC / tot, usable * wW / tot)
    }

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
    private var skyIsDay: Bool {
        if let sr = sunrise, let ss = sunset { return nowTick >= sr && nowTick < ss }
        return (series.first ?? current)?.isDaylight ?? true
    }
    /// Ink for axis text/legends/titles: black by day, white by night when the
    /// sky is shown; otherwise the system color (adapts to light/dark mode).
    private var axisInk: Color { graphSky ? (skyIsDay ? .black : .white) : .primary }
    /// x-position of "now", for the current-time marker line.
    private var nowLineDate: Date? { current?.date ?? series.first?.date }

    private var earliestDate: Date? {
        historic.first?.date ?? current?.date ?? series.first?.date
    }

    private var dateDomain: ClosedRange<Date>? {
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

    private func dayLabel(for date: Date) -> String {
        guard let start = startMidnight, date >= start,
              Calendar.current.component(.hour, from: date) == 0 else { return "" }
        let key = TenDayView.dayFormatter.string(from: date)
        return TenDayView.dayAbbreviations[key] ?? String(key.prefix(2))
    }

    /// The four temperature lines (temp/wet-bulb/dew/apparent) over a set of
    /// points. `suffix` keeps the historic and forecast series distinct so they
    /// are not connected across the "now" boundary; `dash` nil = solid.
    @ChartContentBuilder
    private func tempLines(_ pts: [ForecastPoint], suffix: String, dash: [CGFloat]?) -> some ChartContent {
        ForEach(pts) { p in
            if graphTemp {
                LineMark(x: .value("Time", p.date),
                         y: .value("Temp", useFahrenheit ? p.temperatureF : p.temperatureC),
                         series: .value("S", "A" + suffix))
                    .foregroundStyle(.green).interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: dash ?? []))
            }
            if graphWetBulb {
                LineMark(x: .value("Time", p.date),
                         y: .value("Wet Bulb", useFahrenheit ? p.wetBulbF : p.wetBulbC),
                         series: .value("S", "B" + suffix))
                    .foregroundStyle(.blue).interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: dash ?? []))
            }
            if graphDewPoint {
                LineMark(x: .value("Time", p.date),
                         y: .value("Dew Point", useFahrenheit ? p.dewPointF : p.dewPointC),
                         series: .value("S", "C" + suffix))
                    .foregroundStyle(.red).interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: dash ?? []))
            }
            if graphFeels {
                LineMark(x: .value("Time", p.date),
                         y: .value("Apparent",
                                   useFahrenheit ? p.apparentTemperatureF : p.apparentTemperatureC),
                         series: .value("S", "D" + suffix))
                    .foregroundStyle(.purple).interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: dash ?? []))
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
                    .foregroundStyle(.green).interpolationMethod(.linear)
            }
            if graphWetBulb {
                AreaMark(x: .value("Time", p.date),
                         yStart: .value("base", base),
                         yEnd: .value("Wet Bulb", wet), series: .value("S", "wetA"))
                    .foregroundStyle(.blue).interpolationMethod(.linear)
            }
            if graphDewPoint {
                AreaMark(x: .value("Time", p.date),
                         yStart: .value("base", base),
                         yEnd: .value("Dew Point", dew), series: .value("S", "dewA"))
                    .foregroundStyle(.red).interpolationMethod(.linear)
            }
            if graphFeels {
                LineMark(x: .value("Time", p.date),
                         y: .value("Apparent",
                                   useFahrenheit ? p.apparentTemperatureF : p.apparentTemperatureC),
                         series: .value("S", "appA"))
                    .foregroundStyle(.purple).interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
    }

    /// Gust (always dashed) and wind lines over a set of points. `windDash`
    /// makes the wind line dashed for the historic pass, solid for the forecast.
    @ChartContentBuilder
    private func windLines(_ pts: [ForecastPoint], suffix: String, windDash: [CGFloat]?) -> some ChartContent {
        ForEach(pts) { p in
            if graphGust {
                LineMark(x: .value("Time", p.date),
                         y: .value("Gust", useFahrenheit ? p.windGustMPH : p.windGustKPH),
                         series: .value("S", "G" + suffix))
                    .foregroundStyle(.red.opacity(0.7)).interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, dash: [4, 3]))
                    .symbol(Circle()).symbolSize(0)
            }
            if graphWind {
                LineMark(x: .value("Time", p.date),
                         y: .value("Wind", useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH),
                         series: .value("S", "W" + suffix))
                    .foregroundStyle(.red).interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: windDash ?? []))
                    .symbol(Circle()).symbolSize(0)
            }
        }
    }

    /// Feels-like heatmap: one column per day, hour-of-day on the y-axis, cell
    /// color = personalized feels-like. Separated from the temperature curves
    /// so day-to-day and time-of-day patterns are legible (the curves' x-axis
    /// is time; this grid's y-axis is hour-of-day).
    @ViewBuilder
    private func feelsLikeHeatmap(height: CGFloat) -> some View {
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

    private var heatmapChart: some View {
        let cal = Calendar.current
        return Chart(allPoints) { p in
            let dayStart = cal.startOfDay(for: p.date)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let hour = cal.component(.hour, from: p.date)
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
            .foregroundStyle(myFeelsLikeHeatColor(p))
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
            AxisMarks(values: .stride(by: .day, count: 1)) { value in
                AxisValueLabel {
                    Text(value.as(Date.self).map { dayLabel(for: $0) } ?? "")
                        .font(.caption).foregroundStyle(axisInk)
                }
            }
        }
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
            ScrollView {
                if series.isEmpty {
                    ForecastLoadingView(progress: progress, nowTick: nowTick, errorMessage: errorMessage)
                        .padding()
                        .frame(minHeight: h)
                } else if verticalSizeClass == .compact {
                    // iPhone landscape: the enabled panels side by side.
                    VStack(spacing: 8) {
                        ScenarioStrip(activeFeatures: activeFeatures)
                        HStack(spacing: 12) {
                            if tempPanelVisible { temperatureChart(height: h * 0.9) }
                            if colorPanelVisible { feelsLikeHeatmap(height: h * 0.9) }
                            if windPanelVisible { precipWindChart(height: h * 0.9) }
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
                }
            }
            .refreshable { await onRefresh?() }
        }
    }

    @ViewBuilder
    private func temperatureChart(height: CGFloat) -> some View {
        // Compute the domain once (O(n)) — reading it inside a per-point
        // ForEach would make it O(n²) and stall scrolling/swiping.
        let dom = tempYDomain
        VStack(alignment: .leading, spacing: 2) {
            // Legend without units — only for the enabled series.
            ChartLegendRow(entries: tempLegendEntries, ink: axisInk)
            .padding(.leading, 36)

            Chart {
                // Past, current and forecast all share the same filled bands;
                // a dashed vertical line marks "now" so the past is still clear.
                tempAreas(allPoints, base: dom.lowerBound)
                if let nx = nowLineDate {
                    RuleMark(x: .value("Now", nx))
                        .foregroundStyle(axisInk.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
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
                AxisMarks(values: .stride(by: .day, count: 1)) { value in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel {
                        Text(value.as(Date.self).map { dayLabel(for: $0) } ?? "")
                            .font(.caption).foregroundStyle(axisInk)
                    }
                }
            }
            .ifLet(dateDomain) { view, domain in view.chartXScale(domain: domain) }
            // Unit annotation just below the topmost y-axis number.
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
        let windPts = historic + series
        VStack(alignment: .leading, spacing: 2) {
            ChartLegendRow(entries: windLegendEntries, ink: axisInk)
            .padding(.leading, 36)

            Chart {
                // Areas back→front over history + forecast: gust (translucent
                // red) → wind (solid red) → rain (solid blue). The gust and
                // wind curves are drawn on top of the rain so they stay readable.
                ForEach(windPts) { p in
                    let gust = useFahrenheit ? p.windGustMPH : p.windGustKPH
                    let wind = useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH
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
                }
                // Wind/gust curves: dashed past, solid future, joined at "now".
                windLines(historicPlus, suffix: "h", windDash: [4, 3])
                windLines(forecastPlus, suffix: "",  windDash: nil)
                if let nx = nowLineDate {
                    RuleMark(x: .value("Now", nx))
                        .foregroundStyle(axisInk.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartLegend(.hidden)
            .chartYScale(domain: dom)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel().font(.caption).foregroundStyle(axisInk)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 1)) { value in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel {
                        Text(value.as(Date.self).map { dayLabel(for: $0) } ?? "")
                            .font(.caption).foregroundStyle(axisInk)
                    }
                }
            }
            .ifLet(dateDomain) { view, domain in view.chartXScale(domain: domain) }
            .frame(height: height - 20)
        }
    }
}
