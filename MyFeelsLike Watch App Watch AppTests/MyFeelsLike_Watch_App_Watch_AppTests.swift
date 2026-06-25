//
//  MyFeelsLike_Watch_App_Watch_AppTests.swift
//  MyFeelsLike Watch App Watch AppTests
//
//  Tests the hourly-frame snapshot the complication consumes.
//

import Testing
import Foundation
@testable import MyFeelsLike_Watch_App_Watch_App

struct ComplicationWriterTests {

    /// Minimal forecast point for the watch target.
    private func fp(_ date: Date, tempC: Double, score: Double?) -> ForecastPoint {
        ForecastPoint(
            date: date, symbolName: "sun.max", isDaylight: true, uvIndex: 0,
            temperatureF: tempC * 9/5 + 32, temperatureC: tempC,
            apparentTemperatureF: tempC * 9/5 + 32, apparentTemperatureC: tempC,
            wetBulbF: 0, wetBulbC: 0, dewPointF: 0, dewPointC: 0,
            precipProbability: 0, precipitationMM: 0,
            windSpeedMPH: 0, windSpeedKPH: 0, windGustMPH: 0, windGustKPH: 0,
            cloudCover: 0, cloudCoverLow: 0, cloudCoverMedium: 0, cloudCoverHigh: 0,
            humidity: 0.5, stationPressurePa: 100_000, myFeelsLikeScore: score)
    }

    @Test func buildsHourlyFramesWithinHorizonAndDayRanges() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cur = fp(now, tempC: 20, score: 500)
        // 72 hourly forecast points (3 days) with varying temp/score.
        let series = (1...72).map { h in
            fp(now.addingTimeInterval(Double(h) * 3600),
               tempC: 20 + Double(h % 10), score: 400 + Double(h % 10) * 10)
        }

        let snap = WatchComplicationWriter.build(
            current: cur, series10d: series, hasModel: true, useFahrenheit: false, now: now)!

        // First frame is "now".
        #expect(snap.frames.first?.date == now)
        // Nothing beyond +48 h.
        let horizon = now.addingTimeInterval(48 * 3600 + 1)
        #expect(snap.frames.allSatisfy { $0.date <= horizon })

        // A mid-horizon frame's day temp range matches that calendar day's
        // forecast min/max (build derives day ranges from series10d).
        let cal = Calendar.current
        if let f = snap.frames.first(where: { $0.date >= now.addingTimeInterval(24 * 3600) }) {
            let dayTemps = series
                .filter { cal.isDate($0.date, inSameDayAs: f.date) }
                .map { $0.temperatureC }
            #expect(abs(f.todayTempMaxC - (dayTemps.max() ?? f.todayTempMaxC)) < 1e-6)
            #expect(abs(f.todayTempMinC - (dayTemps.min() ?? f.todayTempMinC)) < 1e-6)
        }
    }

    @Test func noModelUsesMidpointFeels() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let cur = fp(now, tempC: 18, score: nil)
        let series = (1...24).map { h in
            fp(now.addingTimeInterval(Double(h) * 3600), tempC: 18, score: nil)
        }
        let snap = WatchComplicationWriter.build(
            current: cur, series10d: series, hasModel: false, useFahrenheit: false, now: now)!

        #expect(snap.hasModel == false)
        // No scores → feels range defaults to 0…1000, current = midpoint 500.
        #expect(abs((snap.frames.first?.feelsCurrent ?? 0) - 500) < 1e-6)
    }
}
