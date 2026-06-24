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
                VStack(spacing: 6) {
                    if model.series24h.isEmpty {
                        placeholder
                    } else {
                        label("24-hour")
                        tempChart.frame(height: 140)
                        label("Wind / precip")
                        windChart.frame(height: 100)
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
                        .font(.system(size: 15, weight: .semibold))
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

    private var tempChart: some View {
        Chart(model.series24h) { p in
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
            watchFeelsChartBackground(proxy, series: model.series24h, domain: domain)
        }
        .chartYScale(domain: tempYDomain)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(); AxisValueLabel().font(.system(size: 13))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour(), centered: true)
                    .font(.system(size: 13))
            }
        }
    }

    private var windChart: some View {
        Chart(model.series24h) { p in
            AreaMark(x: .value("t", p.date), y: .value("precip", p.precipProbability * 100))
                .foregroundStyle(.blue.opacity(0.3))
            LineMark(x: .value("t", p.date),
                     y: .value("wind", useF ? p.windSpeedMPH : p.windSpeedKPH),
                     series: .value("s", "wind"))
                .foregroundStyle(.red)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(); AxisValueLabel().font(.system(size: 13))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour(), centered: true)
                    .font(.system(size: 13))
            }
        }
    }
}
