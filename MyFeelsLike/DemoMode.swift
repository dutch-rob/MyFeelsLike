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

    /// A pretty 24-hour series, a 10-day (240 h) series, and the "now" point.
    static func forecast(now: Date = Date()) -> (s24: [ForecastPoint],
                                                 s10: [ForecastPoint],
                                                 current: ForecastPoint) {
        let cal = Calendar.current
        let startHour = cal.dateInterval(of: .hour, for: now)?.start ?? now

        func makePoint(hoursFromStart h: Int, kind: ForecastPoint.Kind = .forecast) -> ForecastPoint {
            let date = startHour.addingTimeInterval(Double(h) * 3600)
            let hod = Double(cal.component(.hour, from: date))
            let dayOffset = Double(h / 24)
            // Daily swing 12…24 °C, plus a gentle multi-day drift.
            let tempC = 18 + 6 * sin(2 * .pi * (hod - 9) / 24) + dayOffset * 0.4
            let apparentC = tempC - 1.5
            let dewC = tempC - 8
            let wetC = (tempC + dewC) / 2 + 0.5
            let windKPH = 8 + 6 * sin(2 * .pi * hod / 24)
            let uv = max(0, 7 * sin(.pi * (hod - 6) / 12))
            let daylight = hod >= 6 && hod <= 19
            return point(date: date, kind: kind, tempC: tempC, apparentC: apparentC,
                         wetBulbC: wetC, dewC: dewC, windKPH: windKPH, uv: uv,
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
        [
            Place(name: "San Francisco", latitude: 37.7749, longitude: -122.4194, altitude: 16),
            Place(name: "Denver",        latitude: 39.7392, longitude: -104.9903, altitude: 1609),
            Place(name: "Phoenix",       latitude: 33.4484, longitude: -112.0740, altitude: 331),
        ]
    }

    // MARK: - Builder

    private static func point(date: Date, kind: ForecastPoint.Kind, tempC: Double,
                              apparentC: Double, wetBulbC: Double, dewC: Double,
                              windKPH: Double, uv: Double, daylight: Bool) -> ForecastPoint {
        ForecastPoint(
            kind: kind, date: date,
            symbolName: daylight ? "sun.max.fill" : "moon.stars.fill",
            isDaylight: daylight, uvIndex: uv,
            temperatureF: tempC * 9/5 + 32, temperatureC: tempC,
            apparentTemperatureF: apparentC * 9/5 + 32, apparentTemperatureC: apparentC,
            wetBulbF: wetBulbC * 9/5 + 32, wetBulbC: wetBulbC,
            dewPointF: dewC * 9/5 + 32, dewPointC: dewC,
            precipProbability: 0.1, precipitationMM: 0,
            windSpeedMPH: windKPH / 1.60934, windSpeedKPH: windKPH,
            windGustMPH: windKPH * 1.4 / 1.60934, windGustKPH: windKPH * 1.4,
            cloudCover: 0.3, cloudCoverLow: 0.2, cloudCoverMedium: 0.1, cloudCoverHigh: 0.1,
            humidity: 0.5, stationPressurePa: 101_000)
    }
}
