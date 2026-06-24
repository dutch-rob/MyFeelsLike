//
//  WatchTenDayView.swift
//  MyFeelsLike Watch App
//
//  10-day temperature overview with the MyFeelsLike colour background.
//

import SwiftUI
import Charts

struct WatchTenDayView: View {
    @ObservedObject var model: WatchWeatherModel
    @State private var showPlaces = false
    private var useF: Bool { WatchSyncReceiver.shared.payload?.useFahrenheit ?? false }

    private var domain: ClosedRange<Date>? {
        guard let f = model.series10d.first?.date,
              let l = model.series10d.last?.date else { return nil }
        return f...l
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

    private var tempChart: some View {
        Chart(model.series10d) { p in
            LineMark(x: .value("t", p.date),
                     y: .value("temp", useF ? p.temperatureF : p.temperatureC),
                     series: .value("s", "temp"))
                .foregroundStyle(.blue)
            LineMark(x: .value("t", p.date),
                     y: .value("wet", useF ? p.wetBulbF : p.wetBulbC),
                     series: .value("s", "wet"))
                .foregroundStyle(.green)
            LineMark(x: .value("t", p.date),
                     y: .value("dew", useF ? p.dewPointF : p.dewPointC),
                     series: .value("s", "dew"))
                .foregroundStyle(.red)
            LineMark(x: .value("t", p.date),
                     y: .value("app", useF ? p.apparentTemperatureF : p.apparentTemperatureC),
                     series: .value("s", "app"))
                .foregroundStyle(.purple)
        }
        .chartBackground { proxy in
            watchFeelsChartBackground(proxy, series: model.series10d, domain: domain)
        }
        .chartYScale(domain: tempYDomain)
        .chartYAxis { tempYAxis(useF: useF) }
        .chartXAxis { dailyXAxis() }
    }

    private var windChart: some View {
        Chart(model.series10d) { p in
            AreaMark(x: .value("t", p.date), y: .value("precip", p.precipProbability * 100))
                .foregroundStyle(.blue.opacity(0.3))
            LineMark(x: .value("t", p.date),
                     y: .value("wind", useF ? p.windSpeedMPH : p.windSpeedKPH),
                     series: .value("s", "wind"))
                .foregroundStyle(.red)
        }
        .chartYAxis { plainYAxis() }
        .chartXAxis { dailyXAxis() }
    }
}
