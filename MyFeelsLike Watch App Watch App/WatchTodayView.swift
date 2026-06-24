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

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                placeHeader
                if model.series24h.isEmpty {
                    placeholder
                } else {
                    label("24-hour")
                    tempChart.frame(height: 120)
                    label("Wind / precip")
                    windChart.frame(height: 100)
                }
            }
            .padding(.horizontal, 4)
        }
        .sheet(isPresented: $showPlaces) {
            NavigationStack { WatchPlacesView(model: model) }
        }
    }

    private var placeHeader: some View {
        Button { showPlaces = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "mappin.and.ellipse").font(.system(size: 11))
                Text(model.placeName)
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
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
        .chartYScale(domain: .automatic(includesZero: false))
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
