//
//  WatchTenDayView.swift
//  MyFeelsLike Watch App
//
//  10-day overview. Mirrors the phone's portrait layout: the temperature
//  curves and the personalized feels-like color are shown separately —
//  the curves stay uncolored, and the feels-like score is a heatmap panel
//  (one column per day, hour-of-day up the y-axis) below them.
//

import SwiftUI
import Charts

struct WatchTenDayView: View {
    @ObservedObject var model: WatchWeatherModel
    @State private var showPlaces = false
    private var useF: Bool { WatchSyncReceiver.shared.payload?.useFahrenheit ?? false }

    /// Whether the forecast carries personalized feels-like scores yet.
    private var hasModel: Bool {
        model.series10d.contains { $0.myFeelsLikeScore != nil }
    }

    /// Tight y-range covering the four temperature curves (+ small padding).
    private var tempYDomain: ClosedRange<Double> {
        let vals = model.series10d.flatMap { p -> [Double] in
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
                VStack(spacing: 6) {
                    if model.series10d.isEmpty {
                        VStack { ProgressView() }
                            .frame(maxWidth: .infinity, minHeight: 150)
                    } else {
                        label("10-day")
                        tempChart.frame(height: 140)
                        label("MyFeelsLike by time of day")
                        heatmapPanel.frame(height: 120)
                        label("Wind / precip")
                        windChart.frame(height: 150)
                    }
                }
                .padding(.horizontal, 4)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showPlaces = true } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.and.ellipse")
                            Text(model.placeName).lineLimit(1)
                        }
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

    // MARK: Temperature curves (no feels-like background — see heatmap below)

    private var tempChart: some View {
        let base = tempYDomain.lowerBound
        return Chart(model.series10d) { p in
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
        .chartXAxis { dailyXAxis() }
    }

    // MARK: Feels-like heatmap (one column per day, hour-of-day on the y-axis)

    @ViewBuilder private var heatmapPanel: some View {
        if hasModel {
            heatmapChart
        } else {
            noModelPanel
        }
    }

    private var heatmapChart: some View {
        let cal = Calendar.current
        return Chart(model.series10d) { p in
            let dayStart = cal.startOfDay(for: p.date)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let hour = cal.component(.hour, from: p.date)
            RectangleMark(
                xStart: .value("day", dayStart),
                xEnd:   .value("day end", dayEnd),
                yStart: .value("hour", hour),
                yEnd:   .value("hour end", hour + 1)
            )
            .foregroundStyle(heatColor(p))
        }
        .chartYScale(domain: 0...24)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 6, 12, 18, 24]) { v in
                AxisValueLabel {
                    Text(String(format: "%02d", v.as(Int.self) ?? 0))
                        .font(.system(size: 13))
                }
            }
        }
        .chartXAxis { dailyXAxis() }
    }

    /// Compact gray panel shown until a personalized model exists.
    private var noModelPanel: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.18))
            .overlay(
                Text("No personalized color yet — rate more on your phone.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(8)
            )
    }

    private func heatColor(_ p: ForecastPoint) -> Color {
        guard let s = p.myFeelsLikeScore else { return Color.gray.opacity(0.25) }
        let alpha = max(0.25, min(1, p.myFeelsLikeOpacity))
        return ColorScale.color(forScore: s).opacity(alpha)
    }

    // MARK: Wind / precip

    // Wind/precip matching the phone: areas back→front — gust (translucent red),
    // wind (solid red), precip chance (solid blue) — with a dashed gust line and
    // a solid wind line on top.
    private var windChart: some View {
        Chart(model.series10d) { p in
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
        .chartXAxis { dailyXAxis() }
    }
}
