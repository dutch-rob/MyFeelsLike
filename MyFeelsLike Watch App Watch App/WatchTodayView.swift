//
//  WatchTodayView.swift
//  MyFeelsLike Watch App
//
//  Start screen: the 24-hour temperature graph, with the wind/precip graph
//  below it (scroll up to reach it). Both carry the MyFeelsLike colour
//  background where the model is confident.
//

import SwiftUI
import Charts

struct WatchTodayView: View {
    @ObservedObject var model: WatchWeatherModel
    @State private var showPlaces = false
    private var useF: Bool { WatchSyncReceiver.shared.payload?.useFahrenheit ?? false }

    private var domain: ClosedRange<Date>? {
        guard let f = model.series24h.first?.date,
              let l = model.series24h.last?.date else { return nil }
        return f...l
    }

    /// Whether the forecast carries personalised feels-like scores yet.
    private var hasModel: Bool {
        model.series24h.contains { $0.myFeelsLikeScore != nil }
    }

    /// Whether the model learned a sun effect — the colour band splits into an
    /// in-sun (top) and in-shade (bottom) half only when it did.
    private var sunFeatureActive: Bool {
        WatchSyncReceiver.shared.payload?.regressionState?.selectedFeatures.contains(.sun) ?? false
    }

    /// Tight y-range covering the four temperature curves (+ small padding).
    private var tempYDomain: ClosedRange<Double> {
        let vals = model.series24h.flatMap { p -> [Double] in
            useF ? [p.temperatureF, p.wetBulbF, p.dewPointF, p.apparentTemperatureF]
                 : [p.temperatureC, p.wetBulbC, p.dewPointC, p.apparentTemperatureC]
        }
        guard let lo = vals.min(), let hi = vals.max() else { return 0...1 }
        let pad = max(1, (hi - lo) * 0.08)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 4) {
                    if model.series24h.isEmpty {
                        placeholder
                    } else {
                        // No "24-hour" title: keeping the temp chart compact and
                        // the spacing tight lets the MyFeelsLike colour band show
                        // without scrolling when the screen first opens.
                        tempChart.frame(height: 108)
                        if hasModel {
                            label(sunFeatureActive ? "MyFeelsLike — sun / shade" : "MyFeelsLike")
                            if sunFeatureActive { splitColourBand.frame(height: 30) }
                            else { colourBand.frame(height: 24) }
                        }
                        label("Wind / precip")
                        windChart.frame(height: 150)
                    }
                }
                .padding(.horizontal, 4)
            }
            // Place name in the system top bar (left of the clock). watchOS
            // reserves the clock's space automatically; long names truncate.
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showPlaces = true } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.and.ellipse")
                            Text(model.placeName).lineLimit(1)
                        }
                        // watchOS controls the top-bar title font size, so a
                        // .font(...) here is ignored — only colour applies.
                        // (Change colour here; size isn't adjustable in this slot.)
                        .foregroundStyle(.cyan)
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $showPlaces) {
                NavigationStack { WatchPlacesView(model: model) }
            }
        }
    }

    @ViewBuilder private func label(_ s: String) -> some View {
        Text(s).font(.system(size: 11)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            if model.isLoading { ProgressView() }
            if let e = model.errorText {
                Text(e).font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Loading…").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    // Temperature as filled bands from the axis baseline up to each curve
    // (green = dry bulb, blue = wet bulb, red = dew point), drawn back→front,
    // with the feels-like line on top — matching the phone. The MyFeelsLike
    // colour now lives in its own band below, not behind this chart.
    private var tempChart: some View {
        let base = tempYDomain.lowerBound
        return Chart(model.series24h) { p in
            AreaMark(x: .value("t", p.date),
                     yStart: .value("base", base),
                     yEnd: .value("temp", useF ? p.temperatureF : p.temperatureC),
                     series: .value("s", "dry"))
                .foregroundStyle(.green).interpolationMethod(.linear)
            AreaMark(x: .value("t", p.date),
                     yStart: .value("base", base),
                     yEnd: .value("wet", useF ? p.wetBulbF : p.wetBulbC),
                     series: .value("s", "wet"))
                .foregroundStyle(.blue).interpolationMethod(.linear)
            AreaMark(x: .value("t", p.date),
                     yStart: .value("base", base),
                     yEnd: .value("dew", useF ? p.dewPointF : p.dewPointC),
                     series: .value("s", "dew"))
                .foregroundStyle(.red).interpolationMethod(.linear)
            LineMark(x: .value("t", p.date),
                     y: .value("app", useF ? p.apparentTemperatureF : p.apparentTemperatureC),
                     series: .value("s", "app"))
                .foregroundStyle(.purple).interpolationMethod(.linear)
        }
        .chartYScale(domain: tempYDomain)
        .chartYAxis { tempYAxis(useF: useF) }
        .chartXAxis { hourlyXAxis() }
    }

    /// Thin MyFeelsLike colour band, one cell per hour, time-aligned with the
    /// temperature chart above (own clear y-axis reserves the same leading gap).
    private var colourBand: some View {
        Chart(model.series24h) { p in
            // Cell spans the hour ending at p.date (shifted ~1h left, as on the
            // phone) so it lines up with the temperature curve above.
            RectangleMark(
                xStart: .value("t0", p.date.addingTimeInterval(-3600)),
                xEnd:   .value("t1", p.date),
                yStart: .value("y0", 0),
                yEnd:   .value("y1", 1)
            )
            .foregroundStyle(watchHeatColor(p))
        }
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0]) {
                AxisValueLabel { Text("00").font(.system(size: 13)).foregroundStyle(.clear) }
            }
        }
        .chartXAxis(.hidden)
        .chartXScale(domain: domain ?? Date()...Date())
    }

    /// Split colour band: top half = in full sun, bottom half = in shade, with
    /// tiny sun/shade markers in the leading gutter and a hairline divider.
    private var splitColourBand: some View {
        Chart {
            ForEach(model.series24h) { p in
                let x0 = p.date.addingTimeInterval(-3600)   // hour ending at p.date
                RectangleMark(xStart: .value("t0", x0), xEnd: .value("t1", p.date),
                              yStart: .value("y0", 0.5), yEnd: .value("y1", 1.0))
                    .foregroundStyle(watchScoreColor(p.myFeelsLikeSunScore, opacity: p.myFeelsLikeSunOpacity))
                RectangleMark(xStart: .value("t0", x0), xEnd: .value("t1", p.date),
                              yStart: .value("y0", 0.0), yEnd: .value("y1", 0.5))
                    .foregroundStyle(watchScoreColor(p.myFeelsLikeShadeScore, opacity: p.myFeelsLikeShadeOpacity))
            }
            RuleMark(y: .value("mid", 0.5))
                .foregroundStyle(.white.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 0.5))
        }
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.25, 0.75]) { v in
                AxisValueLabel {
                    Image(systemName: (v.as(Double.self) ?? 0) > 0.5 ? "sun.max.fill" : "cloud.fill")
                        .font(.system(size: 10))
                        .frame(width: 18, alignment: .leading)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartXScale(domain: domain ?? Date()...Date())
    }

    // Wind/precip matching the phone: areas back→front — gust (translucent red),
    // wind (solid red), precip chance (solid blue) — with a dashed gust line and
    // a solid wind line on top so both stay readable over the precip block.
    private var windChart: some View {
        Chart(model.series24h) { p in
            AreaMark(x: .value("t", p.date),
                     yStart: .value("base", 0),
                     yEnd: .value("gust", useF ? p.windGustMPH : p.windGustKPH),
                     series: .value("s", "gustA"))
                .foregroundStyle(.red.opacity(0.35)).interpolationMethod(.linear)
            AreaMark(x: .value("t", p.date),
                     yStart: .value("base", 0),
                     yEnd: .value("wind", useF ? p.windSpeedMPH : p.windSpeedKPH),
                     series: .value("s", "windA"))
                .foregroundStyle(.red).interpolationMethod(.linear)
            AreaMark(x: .value("t", p.date),
                     yStart: .value("base", 0),
                     yEnd: .value("precip", p.precipProbability * 100),
                     series: .value("s", "rainA"))
                .foregroundStyle(.blue).interpolationMethod(.linear)
            LineMark(x: .value("t", p.date),
                     y: .value("gust", useF ? p.windGustMPH : p.windGustKPH),
                     series: .value("s", "gustL"))
                .foregroundStyle(.red.opacity(0.7)).interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [3, 2]))
            LineMark(x: .value("t", p.date),
                     y: .value("wind", useF ? p.windSpeedMPH : p.windSpeedKPH),
                     series: .value("s", "windL"))
                .foregroundStyle(.red).interpolationMethod(.linear)
        }
        .chartYAxis { plainYAxis() }
        .chartXAxis { hourlyXAxis() }
    }
}
