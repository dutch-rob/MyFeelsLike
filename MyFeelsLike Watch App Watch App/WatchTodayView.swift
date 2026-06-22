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
    private var useF: Bool { WatchSyncReceiver.shared.payload?.useFahrenheit ?? false }

    private var domain: ClosedRange<Date>? {
        guard let f = model.series24h.first?.date,
              let l = model.series24h.last?.date else { return nil }
        return f...l
    }

    var body: some View {
        ScrollView {
            if model.series24h.isEmpty {
                placeholder
            } else {
                VStack(spacing: 6) {
                    label("24-hour")
                    tempChart.frame(height: 120)
                    label("Wind / precip")
                    windChart.frame(height: 100)
                }
                .padding(.horizontal, 4)
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
                     y: .value("app", useF ? p.apparentTemperatureF : p.apparentTemperatureC),
                     series: .value("s", "app"))
                .foregroundStyle(.purple)
        }
        .chartBackground { proxy in
            watchFeelsChartBackground(proxy, series: model.series24h, domain: domain)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(); AxisValueLabel().font(.system(size: 9))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in AxisGridLine() }
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
                AxisGridLine(); AxisValueLabel().font(.system(size: 9))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in AxisGridLine() }
        }
    }
}
