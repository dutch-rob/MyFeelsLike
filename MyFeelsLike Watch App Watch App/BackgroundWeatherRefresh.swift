//
//  BackgroundWeatherRefresh.swift
//  MyFeelsLike Watch App
//
//  Periodic background refresh so the complication's forecast data updates
//  without opening the app. watchOS delivers WKApplicationRefreshBackgroundTask
//  roughly hourly while the watch is in use (and defers while it sleeps), as
//  long as the complication is on the active face. We fetch for the last-used
//  location, rebuild the snapshot, and reschedule.
//

import Foundation
import CoreLocation
import WeatherKit
import WatchKit

enum BackgroundWeatherRefresh {
    private static let group = "group.robotex.MyFeelsLike"
    private static let weatherService = WeatherKit.WeatherService()

    /// Schedule the next background refresh (~1 hour out by default).
    static func schedule(after seconds: TimeInterval = 3600) {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date().addingTimeInterval(seconds),
            userInfo: nil
        ) { error in
            if let error { print("BG schedule error: \(error.localizedDescription)") }
        }
    }

    /// Perform a background fetch for the last-used location and rewrite the
    /// complication snapshot. Skips if a fresh snapshot already exists.
    static func run() async {
        // Don't spend the budget if the foreground app just refreshed.
        if let snap = ComplicationSnapshot.load(),
           Date().timeIntervalSince(snap.updated) < 50 * 60 {
            return
        }
        guard let loc = lastLocation() else { return }
        do {
            let now = Date()
            let weather = try await weatherService.weather(for: loc)
            let hours = weather.hourlyForecast.forecast
            let payload = syncedPayload()
            let state = payload?.regressionState
            let scenario = payload?.scenario ?? Scenario()
            let useF = payload?.useFahrenheit ?? false

            let s10 = WeatherMapping.mapPoints(from: hours, start: now,
                                               end: now.addingTimeInterval(240 * 3600),
                                               location: loc)
                .map { var p = $0; p.applyPrediction(state: state, scenario: scenario); return p }
            var cur = WeatherMapping.mapCurrent(weather.currentWeather, location: loc)
            cur.applyPrediction(state: state, scenario: scenario)

            WatchComplicationWriter.write(current: cur, series10d: s10,
                                          hasModel: state != nil, useFahrenheit: useF)
        } catch {
            // Leave the previous snapshot in place; try again next cycle.
        }
    }

    // MARK: Last-used location (saved by the foreground fetch)

    static func saveLocation(_ loc: CLLocation) {
        let d = UserDefaults(suiteName: group)
        d?.set(loc.coordinate.latitude, forKey: "bgLat")
        d?.set(loc.coordinate.longitude, forKey: "bgLon")
        d?.set(loc.altitude, forKey: "bgAlt")
    }

    private static func lastLocation() -> CLLocation? {
        let d = UserDefaults(suiteName: group)
        guard let lat = d?.object(forKey: "bgLat") as? Double,
              let lon = d?.object(forKey: "bgLon") as? Double else { return nil }
        let alt = (d?.object(forKey: "bgAlt") as? Double) ?? 0
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: alt, horizontalAccuracy: 1, verticalAccuracy: 1, timestamp: Date())
    }

    private static func syncedPayload() -> WatchSyncPayload? {
        guard let d = UserDefaults(suiteName: group),
              let data = d.data(forKey: "watchSyncPayload") else { return nil }
        return try? JSONDecoder().decode(WatchSyncPayload.self, from: data)
    }
}
