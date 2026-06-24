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
        VStack(spacing: 6) {
            Text("10-day").font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.series10d.isEmpty {
                Spacer(); ProgressView(); Spacer()
            } else {
                chart
            }
        }
        .padding(.horizontal, 4)
    }

    private var chart: some View {
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
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(); AxisValueLabel().font(.system(size: 13))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 2)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday(), centered: true)
                    .font(.system(size: 13))
            }
        }
    }
}
