// SPDX-License-Identifier: GPL-3.0-or-later
//
//  DemoMode.swift
//  MyFeelsLike
//
//  Canned, deterministic data used only when the app is launched with the
//  "-UITestDemo" argument (App Store screenshot automation). It feeds the real
//  rendering pipeline through an in-memory store, so screenshots show genuine
//  UI without touching the network, location, or the user's real ratings.
//

import Foundation

enum DemoMode {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestDemo")
    }

    /// Display name shown as the current place.
    static let placeName = "Adelaide"

    // MARK: - Forecast

    /// A 24-hour series, a 10-day (240 h) series, and the "now" point, all
    /// sourced from a real measured forecast (see DemoForecastAdelaide) so
    /// screenshots show genuine-looking weather rather than a synthetic curve.
    static func forecast(now: Date = Date()) -> (s24: [ForecastPoint],
                                                 s10: [ForecastPoint],
                                                 current: ForecastPoint) {
        let cal = Calendar.current
        let startHour = cal.dateInterval(of: .hour, for: now)?.start ?? now

        let rows = DemoForecastAdelaide.rows
        guard !rows.isEmpty else {
            let fallback = point(date: now, kind: .current, tempC: 20, apparentC: 20,
                                 wetBulbC: 15, dewC: 12, windKPH: 10, uv: 3, daylight: true)
            return ([fallback], [fallback], fallback)
        }

        // Line up the CSV's diurnal cycle with the real current hour (UTC) so
        // "now" doesn't land on a mismatched sun/moon icon or temperature swing.
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let nowUTCHour = utcCal.component(.hour, from: now)
        let phase = rows.prefix(24).firstIndex { utcCal.component(.hour, from: $0.date) == nowUTCHour } ?? 0

        func makePoint(hoursFromStart h: Int, kind: ForecastPoint.Kind = .forecast) -> ForecastPoint {
            let date = startHour.addingTimeInterval(Double(h) * 3600)
            let r = rows[(phase + h) % rows.count]
            return ForecastPoint(
                kind: kind, date: date, symbolName: r.symbol,
                isDaylight: r.isDaylight, uvIndex: r.uv,
                temperatureF: r.tempC * 9/5 + 32, temperatureC: r.tempC,
                apparentTemperatureF: r.apparentC * 9/5 + 32, apparentTemperatureC: r.apparentC,
                wetBulbF: r.wetBulbC * 9/5 + 32, wetBulbC: r.wetBulbC,
                dewPointF: r.dewPointC * 9/5 + 32, dewPointC: r.dewPointC,
                precipProbability: r.precipProb, precipitationMM: r.precipMM,
                windSpeedMPH: r.windKPH / 1.60934, windSpeedKPH: r.windKPH,
                windGustMPH: r.gustKPH / 1.60934, windGustKPH: r.gustKPH,
                cloudCover: r.cloud, cloudCoverLow: r.cloudLow,
                cloudCoverMedium: r.cloudMed, cloudCoverHigh: r.cloudHigh,
                humidity: r.humidity, stationPressurePa: r.pressurePa)
        }

        let s24 = (0..<24).map { makePoint(hoursFromStart: $0) }
        let s10 = (0..<240).map { makePoint(hoursFromStart: $0) }
        let current = makePoint(hoursFromStart: 0, kind: .current)
        return (s24, s10, current)
    }

    // MARK: - Ratings (enough to fit a model so the colors show)

    /// Apparent-temperature band the demo user has "rated in". Deliberately
    /// narrower than the forecast's own range so the screenshots show what a
    /// real model looks like: full-width color where the forecast matches the
    /// conditions that were rated, and a narrowed band (down to the 15% floor)
    /// where it doesn't.
    /// Comfortably wider than the 3 °C a feature needs to be eligible at all,
    /// and sitting in the upper part of the coming day's range so the colder
    /// hours fall outside it.
    static let ratedApparentBand: ClosedRange<Double> = 10.8...14.2

    static func ratings() -> [Rating] {
        // Rate real forecast hours rather than invented ones, so every other
        // observation (humidity, wind, cloud, pressure…) carries a realistic
        // range too and the reliability checks behave as they would in the field.
        let (_, s10, _) = forecast()
        let candidates = s10.filter { ratedApparentBand.contains($0.apparentTemperatureC) }
        guard candidates.count >= 5 else {
            // Fallback for an empty/odd CSV: keep the old synthetic ratings so a
            // model still fits and the demo isn't colorless.
            return stride(from: 5.0, through: 30.0, by: 2.5).map { a in
                let snap = point(date: Date(), kind: .forecast, tempC: a + 1, apparentC: a,
                                 wetBulbC: a - 3, dewC: a - 6, windKPH: 8, uv: 3, daylight: true)
                return Rating(feelsLikeScore: 150 + (a - 5) / 25 * 750,
                              activity: 1, dress: 0, sun: 0, snapshot: snap)
            }
        }
        // Sample evenly across the temperature range, both ends included. Picking
        // by position in time instead left the coldest and warmest rated hours
        // out, and the resulting spread fell just under the 3 °C a feature needs
        // to be eligible at all — so no model was fit and the demo lost its color.
        let sorted = candidates.sorted { $0.apparentTemperatureC < $1.apparentTemperatureC }
        let wanted = min(14, sorted.count)
        return (0..<wanted).map { i in
            let p = sorted[i * (sorted.count - 1) / max(1, wanted - 1)]
            // ~40 points per °C: steep enough to clear the score-spread gate,
            // gentle enough to stay well inside the plausibility ceiling.
            let score = 420 + (p.apparentTemperatureC - ratedApparentBand.lowerBound) * 40
            return Rating(feelsLikeScore: score, activity: 1, dress: 0, sun: 0, snapshot: p)
        }
    }

    // MARK: - Places

    static func places() -> [Place] {
        // First entry matches `placeName` so the main screen agrees with the list.
        [
            Place(name: "Adelaide",      latitude: -34.9285, longitude: 138.6007, altitude: 50),
            Place(name: "Phoenix, AZ",   latitude:  33.4484, longitude: -112.0740, altitude: 331),
            Place(name: "New York",      latitude:  40.7128, longitude:  -74.0060, altitude: 10),
            Place(name: "London",        latitude:  51.5074, longitude:   -0.1278, altitude: 11),
            Place(name: "Tokyo",         latitude:  35.6762, longitude:  139.6503, altitude: 40),
            Place(name: "New Delhi",     latitude:  28.6139, longitude:   77.2090, altitude: 216),
        ]
    }

    // MARK: - Builder

    private static func point(date: Date, kind: ForecastPoint.Kind, tempC: Double,
                              apparentC: Double, wetBulbC: Double, dewC: Double,
                              windKPH: Double, uv: Double,
                              cloud: Double = 0.3, precipProb: Double = 0, precipMM: Double = 0,
                              daylight: Bool) -> ForecastPoint {
        let symbol: String
        if precipProb > 0.4 { symbol = "cloud.rain.fill" }
        else if cloud > 0.6 { symbol = "cloud.fill" }
        else { symbol = daylight ? "sun.max.fill" : "moon.stars.fill" }
        return ForecastPoint(
            kind: kind, date: date,
            symbolName: symbol,
            isDaylight: daylight, uvIndex: uv,
            temperatureF: tempC * 9/5 + 32, temperatureC: tempC,
            apparentTemperatureF: apparentC * 9/5 + 32, apparentTemperatureC: apparentC,
            wetBulbF: wetBulbC * 9/5 + 32, wetBulbC: wetBulbC,
            dewPointF: dewC * 9/5 + 32, dewPointC: dewC,
            precipProbability: precipProb, precipitationMM: precipMM,
            windSpeedMPH: windKPH / 1.60934, windSpeedKPH: windKPH,
            windGustMPH: windKPH * 1.4 / 1.60934, windGustKPH: windKPH * 1.4,
            cloudCover: cloud, cloudCoverLow: cloud * 0.6,
            cloudCoverMedium: cloud * 0.3, cloudCoverHigh: cloud * 0.2,
            humidity: min(0.95, 0.45 + 0.4 * cloud), stationPressurePa: 101_000)
    }
}
