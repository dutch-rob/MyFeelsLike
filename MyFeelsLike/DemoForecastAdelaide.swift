// SPDX-License-Identifier: GPL-3.0-or-later
//
//  DemoForecastAdelaide.swift
//  MyFeelsLike
//
//  Real hourly forecast for Adelaide, SA (Lot 51 Victoria Sq), captured
//  2026-06-27 via the app's own "Export forecast table (CSV)" developer aid.
//  Bundled as DemoForecastAdelaide.csv and parsed once, lazily, for use by
//  DemoMode as realistic stand-in data for App Store screenshots.
//

import Foundation

enum DemoForecastAdelaide {
    struct Row {
        let date: Date
        let tempC, apparentC, wetBulbC, dewPointC, humidity: Double
        let windKPH, gustKPH, precipProb, precipMM: Double
        let cloud, cloudLow, cloudMed, cloudHigh, uv, pressurePa: Double
        let isDaylight: Bool
        let symbol: String
    }

    static let rows: [Row] = {
        guard let url = Bundle.main.url(forResource: "DemoForecastAdelaide", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let iso = ISO8601DateFormatter()
        var result: [Row] = []
        for line in text.split(separator: "\n").dropFirst() {
            let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 18, let date = iso.date(from: f[0]) else { continue }
            result.append(Row(
                date: date,
                tempC: Double(f[1]) ?? 0, apparentC: Double(f[2]) ?? 0,
                wetBulbC: Double(f[3]) ?? 0, dewPointC: Double(f[4]) ?? 0,
                humidity: Double(f[5]) ?? 0,
                windKPH: Double(f[6]) ?? 0, gustKPH: Double(f[7]) ?? 0,
                precipProb: Double(f[8]) ?? 0, precipMM: Double(f[9]) ?? 0,
                cloud: Double(f[10]) ?? 0, cloudLow: Double(f[11]) ?? 0,
                cloudMed: Double(f[12]) ?? 0, cloudHigh: Double(f[13]) ?? 0,
                uv: Double(f[14]) ?? 0, pressurePa: Double(f[15]) ?? 0,
                isDaylight: f[16] == "1",
                symbol: f[17]))
        }
        return result
    }()
}
