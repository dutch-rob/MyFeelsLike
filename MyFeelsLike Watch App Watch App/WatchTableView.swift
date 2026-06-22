//
//  WatchTableView.swift
//  MyFeelsLike Watch App
//
//  Compact hourly table. Fewer columns than the phone (time · feels-colour ·
//  temp/feels · wind) so rows stay legible; scroll with the Digital Crown.
//

import SwiftUI

struct WatchTableView: View {
    @ObservedObject var model: WatchWeatherModel
    private var useF: Bool { WatchSyncReceiver.shared.payload?.useFahrenheit ?? false }

    private static let timeFmt: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE HH"
        return df
    }()

    var body: some View {
        List {
            if model.series10d.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else {
                ForEach(model.series10d) { p in
                    row(p)
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder private func row(_ p: ForecastPoint) -> some View {
        HStack(spacing: 6) {
            Text(Self.timeFmt.string(from: p.date))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
            swatch(p)
            Text(tempText(p)).font(.system(size: 12)).monospacedDigit()
            Spacer()
            Text(windText(p)).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func swatch(_ p: ForecastPoint) -> some View {
        if let s = p.myFeelsLikeScore {
            RoundedRectangle(cornerRadius: 3)
                .fill(ColorScale.color(forScore: s))
                .frame(width: 14, height: 14)
        } else {
            RoundedRectangle(cornerRadius: 3)
                .stroke(.secondary.opacity(0.5))
                .frame(width: 14, height: 14)
        }
    }

    private func tempText(_ p: ForecastPoint) -> String {
        let t = useF ? p.temperatureF : p.temperatureC
        let a = useF ? p.apparentTemperatureF : p.apparentTemperatureC
        return String(format: "%.0f(%.0f)", t, a)
    }

    private func windText(_ p: ForecastPoint) -> String {
        let w = useF ? p.windSpeedMPH : p.windSpeedKPH
        return String(format: "%.0f", w)
    }
}
