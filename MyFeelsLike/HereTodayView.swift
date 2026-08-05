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
    @AppStorage(GraphKey.wetBulb)  private var graphWetBulb  = false
    @AppStorage(GraphKey.dewPoint) private var graphDewPoint = false
    @AppStorage(GraphKey.feels)    private var graphFeels    = true
    @AppStorage(GraphKey.color)   private var graphColor   = true
    @AppStorage(GraphKey.precip)   private var graphPrecip   = true
    @AppStorage(GraphKey.wind)     private var graphWind     = true
    @AppStorage(GraphKey.gust)     private var graphGust     = true
    @AppStorage(GraphKey.sky)      private var graphSky      = true
    @AppStorage(SettingsKey.sunShadeStyle) private var sunShadeStyle = SunShadeStyle.separate
    @AppStorage(SettingsKey.chartSeriesStyle) private var chartStyle = ChartSeriesStyle.lines
    @AppStorage(SettingsKey.graphPalette) private var graphPalette = GraphPalette.vivid
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var linesOnly: Bool { chartStyle == .lines }

    /// The time the user is scrubbing to after a long-press on a chart. A dashed
    /// vertical line is drawn at this time across every panel, and a readout card
    /// (the "table row" for that hour) is anchored to it. nil = not scrubbing.
    @State private var scrubDate: Date? = nil
    /// Plots' on-screen (global) x-range, so a long press between panels maps too.
    @State private var plotXRange: ClosedRange<CGFloat>? = nil

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

    // MARK: Scrubbing (long-press to read a specific hour's values)
    //
    // Two modes so normal swiping/scrolling keeps working:
    //   • Not scrubbing (scrubDate == nil): only a long-press recognizer is
    //     attached, which coexists with the tab pager's horizontal swipe and the
    //     ScrollView's pull-to-refresh. A long press drops the line at "now".
    //   • Scrubbing (scrubDate != nil): a transparent drag layer is added over
    //     each plot so *any* touch moves the line (no second long press needed).
    //     Paging is intentionally suspended until the line is dismissed (✕).

    /// The forecast hour nearest the scrubbed time, if any.
    private var scrubPoint: ForecastPoint? {
        guard let t = scrubDate else { return nil }
        return series.min { abs($0.date.timeIntervalSince(t)) < abs($1.date.timeIntervalSince(t)) }
    }

    /// Always present: a UIKit long-press drops the scrub line exactly where the
    /// finger is (and moves it while holding + dragging), and records the plot's
    /// global x-range so presses in the gaps between panels map too.
    @ViewBuilder
    private func scrubEntry(_ proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            let plot = proxy.plotFrame.map { geo[$0] }
            LongPressLocator { loc, state in
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
            scrubDate = series.min { abs($0.date.timeIntervalSince(t)) < abs($1.date.timeIntervalSince(t)) }?.date
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
        // Snap to the nearest forecast hour so the readout matches a real row.
        scrubDate = series.min {
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

    /// A dashed vertical rule at the scrubbed time. Added inside each chart so
    /// the line spans all panels at the same x. The readout card itself is a
    /// separate HUD overlay on the temperature chart (so it can't be clipped by
    /// the plot bounds the way a top-anchored chart annotation would).
    @ChartContentBuilder
    private func scrubRule() -> some ChartContent {
        if let t = scrubDate {
            RuleMark(x: .value("Scrub", t))
                .foregroundStyle(axisInk.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    /// Compact "table row" for one hour, shown above the scrub line.
    private func scrubReadout(_ p: ForecastPoint) -> some View {
        let unit = useFahrenheit ? "°F" : "°C"
        let windUnit = useFahrenheit ? "mph" : "kph"
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(fullTimeLabel(for: p.date)).font(.subheadline.weight(.semibold))
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
            readoutRow("Temp/feels \(unit)",
                       String(format: "%.1f (%.1f)",
                              useFahrenheit ? p.temperatureF : p.temperatureC,
                              useFahrenheit ? p.apparentTemperatureF : p.apparentTemperatureC),
                       .green)
            readoutRow("Wet bulb \(unit)",
                       String(format: "%.1f", useFahrenheit ? p.wetBulbF : p.wetBulbC), .blue)
            readoutRow("Dew pt \(unit)",
                       String(format: "%.1f", useFahrenheit ? p.dewPointF : p.dewPointC), .red)
            readoutRow("Wind (gust) \(windUnit)",
                       String(format: "%.0f (%.0f)",
                              useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH,
                              useFahrenheit ? p.windGustMPH : p.windGustKPH), .red)
            readoutRow("Precip", String(format: "%.1f mm (%.0f%%)",
                                        p.precipitationMM, p.precipProbability * 100), .blue)
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
        .fixedSize()
    }

    private func readoutRow(_ label: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).font(.footnote.weight(.medium)).monospacedDigit()
                .foregroundStyle(tint.mix(with: .primary, by: 0.25))
        }
    }

    private func fullTimeLabel(for date: Date) -> String {
        let h = Calendar.current.component(.hour, from: date)
        if use12Hour {
            if h == 0 { return "12 am" }
            if h == 12 { return "noon" }
            return h < 12 ? "\(h) am" : "\(h - 12) pm"
        }
        return String(format: "%02d:00", h)
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
                    // A long press between panels scrubs too (panels are caught by
                    // their own entry overlay in front).
                    .background(scrubGapEntry)
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
        let splitActive = sunFeatureActive && hasModel
        // In separate style the title sits between the two bands, and in gradient
        // style it's overlaid inside the band — so it's omitted from the top in
        // both split modes.
        let separateSplit = splitActive && sunShadeStyle == .separate
        let gradientSplit = splitActive && sunShadeStyle == .gradient
        VStack(alignment: .leading, spacing: 2) {
            if !separateSplit && !gradientSplit {
                Text("MyFeelsLike by hour")
                    .font(.caption2).foregroundStyle(axisInk)
                    .padding(.leading, 36)
            }
            if hasModel {
                if sunFeatureActive {
                    if sunShadeStyle == .separate { separateColorBands(height: height) }
                    else { splitColorBand(height: height + 14) }   // reclaim the title row
                }
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

    /// Gradient band: each hour cell runs in-shade (top) → in-sun (bottom) — one
    /// column of the 10-day heatmap turned 90°, so the day's shade↔sun spread
    /// reads vertically. Reliability is carried by cell opacity (the gradient
    /// needs the full height to read). Night cells (sun == shade) fall back to
    /// the solid MyFeelsLike color.
    private func splitColorBand(height: CGFloat) -> some View {
        ZStack {
            Chart {
                ForEach(series) { p in
                    let x0 = p.date.addingTimeInterval(-3600)   // hour ending at p.date
                    let style: AnyShapeStyle = sunShadeGradient(p, vertical: true).map(AnyShapeStyle.init)
                        ?? AnyShapeStyle(bandColor(p.myFeelsLikeScore, opacity: p.myFeelsLikeOpacity))
                    RectangleMark(xStart: .value("t0", x0), xEnd: .value("t1", p.date),
                                  yStart: .value("y0", 0), yEnd: .value("y1", 1))
                        .foregroundStyle(style)
                }
            }
            .chartYScale(domain: 0...1)
            // Tiny shade/sun markers in the leading gutter (cloud on top, sun below)
            // cue the vertical direction; they also reserve the leading width so the
            // band lines up with the temperature chart above.
            .chartYAxis {
                AxisMarks(position: .leading, values: [0.25, 0.75]) { v in
                    AxisValueLabel {
                        Image(systemName: (v.as(Double.self) ?? 0) > 0.5 ? "cloud.fill" : "sun.max.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(axisInk)
                            .frame(width: 16, alignment: .leading)
                    }
                }
            }
            .chartXAxis(.hidden)
            .ifLet(dateDomain) { view, domain in view.chartXScale(domain: domain) }

            // Title in the middle of the band, outlined so it stays legible over
            // whatever colors sit under it (like the watch complication number).
            // "shade / sun" matches the band's order (in-shade on top, in-sun
            // below).
            OutlinedText(text: "MyFeelsLike — shade / sun", fill: .white, outline: .black, width: 1.3)
                .font(.system(size: 12, weight: .bold))
                .padding(.leading, 36)
        }
        .frame(height: height)
    }

    /// Separate style: two stacked solid bands — in-shade (all hours) above, and
    /// in-sun (daytime only, night left blank) below. Both share the same time
    /// axis, so the sun band lines up under the shade band and simply has gaps
    /// where there's no daylight. Cloud/sun markers label each.
    private func separateColorBands(height: CGFloat) -> some View {
        // Reserve a row for the centered title; split the rest between the bands.
        let barH = max(10, (height - 18) / 2)
        return VStack(spacing: 3) {
            soloBand(icon: "cloud.fill", height: barH) { p in
                (p.myFeelsLikeShadeScore ?? p.myFeelsLikeScore).map {
                    ColorScale.feelsColor(score: $0, opacity: p.myFeelsLikeShadeOpacity, floor: 0.2)
                }
            }
            // Title centered between the two bands, for symmetry.
            Text("MyFeelsLike by hour")
                .font(.caption2).foregroundStyle(axisInk)
                .padding(.leading, 36)
            soloBand(icon: "sun.max.fill", height: barH) { p in
                guard p.isDaylight, let s = p.myFeelsLikeSunScore else { return nil }
                return ColorScale.feelsColor(score: s, opacity: p.myFeelsLikeSunOpacity, floor: 0.2)
            }
        }
    }

    /// One solid color band (reliability as thickness). `color` returns nil to
    /// leave an hour blank (used to drop night from the in-sun band).
    private func soloBand(icon: String, height: CGFloat,
                          color: @escaping (ForecastPoint) -> Color?) -> some View {
        Chart {
            ForEach(series) { p in
                if let c = color(p) {
                    let half = myFeelsLikeReliability(p) / 2
                    RectangleMark(xStart: .value("t0", p.date.addingTimeInterval(-3600)),
                                  xEnd:   .value("t1", p.date),
                                  yStart: .value("y0", 0.5 - half), yEnd: .value("y1", 0.5 + half))
                        .foregroundStyle(c)
                }
            }
        }
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.5]) { _ in
                AxisValueLabel {
                    Image(systemName: icon).font(.system(size: 9))
                        .foregroundStyle(axisInk).frame(width: 16, alignment: .leading)
                }
            }
        }
        .chartXAxis(.hidden)
        .ifLet(dateDomain) { view, domain in view.chartXScale(domain: domain) }
        .frame(height: height)
        // Title overlaid in the middle of the band, outlined so it stays legible
        // over whatever colors sit under it (like the watch complication number).
        .overlay {
            OutlinedText(text: "MyFeelsLike — sun / shade", fill: .white, outline: .black, width: 1.5)
                .font(.system(size: 14, weight: .bold))
                .padding(.leading, 36)
        }
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
                        if linesOnly {
                            LineMark(x: .value("Time", p.date), y: .value("Temp", dry),
                                     series: .value("S", "dry"))
                                .foregroundStyle(.green).interpolationMethod(.linear)
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                        } else {
                            AreaMark(x: .value("Time", p.date),
                                     yStart: .value("base", base),
                                     yEnd: .value("Temp", dry),
                                     series: .value("S", "dry"))
                                .foregroundStyle(.green).interpolationMethod(.linear)
                        }
                    }
                    if graphWetBulb {
                        if linesOnly {
                            LineMark(x: .value("Time", p.date), y: .value("Wet Bulb", wet),
                                     series: .value("S", "wet"))
                                .foregroundStyle(.blue).interpolationMethod(.linear)
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                        } else {
                            AreaMark(x: .value("Time", p.date),
                                     yStart: .value("base", base),
                                     yEnd: .value("Wet Bulb", wet),
                                     series: .value("S", "wet"))
                                .foregroundStyle(.blue).interpolationMethod(.linear)
                        }
                    }
                    if graphDewPoint {
                        if linesOnly {
                            LineMark(x: .value("Time", p.date), y: .value("Dew Point", dew),
                                     series: .value("S", "dew"))
                                .foregroundStyle(.red).interpolationMethod(.linear)
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                        } else {
                            AreaMark(x: .value("Time", p.date),
                                     yStart: .value("base", base),
                                     yEnd: .value("Dew Point", dew),
                                     series: .value("S", "dew"))
                                .foregroundStyle(.red).interpolationMethod(.linear)
                        }
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
                scrubRule()
            }
            // MyFeelsLike color now lives in its own panel below (see
            // myFeelsLikePanel), matching the 10-day screen's heatmap.
            .chartLegend(.hidden)
            // Long press drops the scrub line; a drag layer (added only while
            // scrubbing) then moves it on any touch. Keeping the drag layer out
            // of the idle state leaves swiping and pull-to-refresh working.
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
                // Labels sit at their tick (not centered on the 2-hour interval),
                // so an hour label lines up with the gridline/scrub line at that
                // exact time rather than reading an hour off.
                AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel {
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
            // Scrub readout HUD — the "table row" for the long-pressed hour. It
            // sits on the side opposite the line so the graph under the line
            // stays visible, and carries its own ✕ to dismiss. Placed after the
            // drag layer so its button stays tappable.
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
        .saturation(graphPalette.saturation)
    }

    @ViewBuilder
    private func precipWindChart(height: CGFloat) -> some View {
        // Compute the domain once (O(n)); reading it per-point would be O(n²).
        let dom = windYDomain
        let base = dom.lowerBound
        VStack(alignment: .leading, spacing: 2) {
            Chart {
                ForEach(series) { p in
                    let gust = useFahrenheit ? p.windGustMPH : p.windGustKPH
                    let wind = useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH
                    // Areas back→front: gust (translucent red) → wind (solid
                    // red) → rain (solid blue). The gust and wind curves are
                    // then drawn on top of the rain so they stay readable.
                    if graphGust && !linesOnly {
                        AreaMark(x: .value("Time", p.date),
                                 yStart: .value("base", base),
                                 yEnd: .value("Gust", gust), series: .value("S", "gustA"))
                            .foregroundStyle(.red.opacity(0.35)).interpolationMethod(.linear)
                    }
                    if graphWind && !linesOnly {
                        AreaMark(x: .value("Time", p.date),
                                 yStart: .value("base", base),
                                 yEnd: .value("Wind", wind), series: .value("S", "windA"))
                            .foregroundStyle(.red).interpolationMethod(.linear)
                    }
                    if graphPrecip {
                        if linesOnly {
                            LineMark(x: .value("Time", p.date),
                                     y: .value("Precip %", p.precipProbability * 100),
                                     series: .value("S", "rainL"))
                                .foregroundStyle(.blue).interpolationMethod(.linear)
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                        } else {
                            AreaMark(x: .value("Time", p.date),
                                     yStart: .value("base", base),
                                     yEnd: .value("Precip %", p.precipProbability * 100), series: .value("S", "rainA"))
                                .foregroundStyle(.blue).interpolationMethod(.linear)
                        }
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
                scrubRule()
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in scrubEntry(proxy) }
            .chartOverlay { proxy in if scrubDate != nil { scrubDragLayer(proxy) } }
            // Area mode flips the scale — zero at the top (nearest the color
            // bar), so the wind/rain areas hang downward and share the hour
            // labels of the temperature chart above. Lines mode reads the normal
            // way up (zero at the bottom), matching the temperature panel.
            .chartYScale(domain: linesOnly ? [dom.lowerBound, dom.upperBound]
                                            : [dom.upperBound, dom.lowerBound])
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 5)) { _ in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel().font(.caption).foregroundStyle(axisInk)
                }
            }
            .chartXAxis {
                // Grid lines only — the hour labels are shared with the chart above.
                AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                }
            }
            .ifLet(dateDomain) { view, domain in view.chartXScale(domain: domain) }
            .frame(height: height - 20)

            // Legend below the panel (moved from the top), near the largest values.
            ChartLegendRow(entries: windLegendEntries, ink: axisInk)
                .padding(.leading, 36)
        }
        .saturation(graphPalette.saturation)
    }
}

// MARK: - Outlined text (legible over any background)

/// Text drawn with a contrasting outline (8-direction stroke + fill on top), so
/// it stays readable over a varying color band — the same technique used for the
/// number in the round watch complication.
private struct OutlinedText: View {
    let text: String
    let fill: Color
    let outline: Color
    var width: CGFloat = 1

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
