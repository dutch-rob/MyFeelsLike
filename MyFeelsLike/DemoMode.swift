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
    static let placeName = "San Francisco"

    // MARK: - Forecast

    // Per-day character over 10 days: a temperature offset (°C) and a rain
    // "intensity" 0…1. A cool, wet spell sits mid-period (days 4–6).
    // NOTE: this is hand-made stand-in data. To use a real forecast for
    // screenshots, replace these arrays (and the formula below) with measured
    // hourly values — the rest of the app reads only the produced ForecastPoints.
    private static let dayTempOffset: [Double] = [0, 1.5, 0.5, -1, -4, -3, 0.5, 2, 1, 2.5]
    private static let dayRain:       [Double] = [0.05, 0.10, 0.25, 0.60, 0.85, 0.55, 0.15, 0.05, 0.10, 0.05]

    /// A 24-hour series, a 10-day (240 h) series, and the "now" point.
    static func forecast(now: Date = Date()) -> (s24: [ForecastPoint],
                                                 s10: [ForecastPoint],
                                                 current: ForecastPoint) {
        let cal = Calendar.current
        let startHour = cal.dateInterval(of: .hour, for: now)?.start ?? now

        func makePoint(hoursFromStart h: Int, kind: ForecastPoint.Kind = .forecast) -> ForecastPoint {
            let date = startHour.addingTimeInterval(Double(h) * 3600)
            let hod  = Double(cal.component(.hour, from: date))
            let day  = min(9, h / 24)
            let rain = dayRain[day]
            // Irregular hour-to-hour wiggle so curves don't look like pure sines.
            let noise = 0.7 * sin(Double(h) * 1.3) + 0.4 * sin(Double(h) * 0.45 + 1)
            let tempC = 18 + dayTempOffset[day] + 6 * sin(2 * .pi * (hod - 9) / 24) + noise
            let apparentC = tempC - 1.2 - 0.6 * sin(Double(h) * 0.8)
            let dewC = tempC - 7 + 3 * rain                       // more humid when rainy
            let wetC = (tempC + dewC) / 2 + 0.4
            let windKPH = max(2, 9 + 7 * sin(2 * .pi * hod / 24 + 0.5) + 5 * rain + 2 * sin(Double(h) * 0.6))
            let uv = max(0, 7 * sin(.pi * (hod - 6) / 12) * (1 - 0.6 * rain))
            let cloud = min(1, 0.2 + rain + 0.12 * sin(Double(h) * 0.5))
            // Daytime-weighted chance of rain; mm only on the wetter hours.
            let precipProb = max(0, rain * sin(.pi * max(0, hod - 4) / 16))
            let precipMM = precipProb > 0.4 ? (precipProb - 0.4) * 5 : 0
            let daylight = hod >= 6 && hod <= 19
            return point(date: date, kind: kind, tempC: tempC, apparentC: apparentC,
                         wetBulbC: wetC, dewC: dewC, windKPH: windKPH, uv: uv,
                         cloud: cloud, precipProb: precipProb, precipMM: precipMM,
                         daylight: daylight)
        }

        let s24 = (0..<24).map { makePoint(hoursFromStart: $0) }
        let s10 = (0..<240).map { makePoint(hoursFromStart: $0) }
        let current = makePoint(hoursFromStart: 0, kind: .current)
        return (s24, s10, current)
    }

    // MARK: - Ratings (enough to fit a model so the colours show)

    static func ratings() -> [Rating] {
        // Apparent 5…30 °C → score 150…900 (spread 750 ≥ 80) so canFit passes.
        stride(from: 5.0, through: 30.0, by: 2.5).map { a in
            let score = 150 + (a - 5) / 25 * 750
            let snap = point(date: Date(), kind: .forecast, tempC: a + 1, apparentC: a,
                             wetBulbC: a - 3, dewC: a - 6, windKPH: 8, uv: 3, daylight: true)
            return Rating(feelsLikeScore: score, activity: 1, dress: 0, sun: 0, snapshot: snap)
        }
    }

    // MARK: - Places

    static func places() -> [Place] {
        // First entry matches `placeName` so the main screen agrees with the list.
        [
            Place(name: "San Francisco", latitude: 37.7749, longitude: -122.4194, altitude: 16),
            Place(name: "Denver",        latitude: 39.7392, longitude: -104.9903, altitude: 1609),
            Place(name: "New York",      latitude: 40.7128, longitude:  -74.0060, altitude: 10),
            Place(name: "London",        latitude: 51.5074, longitude:   -0.1278, altitude: 11),
            Place(name: "Tokyo",         latitude: 35.6762, longitude:  139.6503, altitude: 40),
            Place(name: "Sydney",        latitude: -33.8688, longitude: 151.2093, altitude: 58),
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
