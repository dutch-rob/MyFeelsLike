//
//  WatchWeatherModel.swift
//  MyFeelsLike Watch App
//
//  Fetches the watch's own location + WeatherKit forecast, maps it with the
//  shared WeatherMapping, applies the synced regression model, and writes the
//  complication snapshot. Re-applying the model (e.g. after a fresh sync) does
//  not require a new fetch.
//

import Foundation
import CoreLocation
import WeatherKit
import Combine
import WidgetKit

@MainActor
final class WatchWeatherModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var series24h: [ForecastPoint] = []
    @Published var series10d: [ForecastPoint] = []
    @Published var current: ForecastPoint?
    @Published var isLoading = false
    @Published var errorText: String?
    /// nil = current location; otherwise a place synced from the phone.
    @Published var selectedPlace: PlaceDTO?

    var placeName: String { selectedPlace?.name ?? "Current Location" }

    private let manager = CLLocationManager()
    private let weatherService = WeatherKit.WeatherService()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.requestWhenInUseAuthorization()
    }

    func refresh() {
        isLoading = true
        if let p = selectedPlace {
            let loc = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude),
                altitude: p.altitude, horizontalAccuracy: 1, verticalAccuracy: 1, timestamp: Date())
            Task { await load(for: loc) }
        } else {
            manager.requestLocation()
        }
    }

    /// Switch to a place (nil = back to current location) and refetch.
    func select(_ place: PlaceDTO?) {
        selectedPlace = place
        refresh()
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let loc = locs.last else { return }
        Task { await self.load(for: loc) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorText = error.localizedDescription
            self.isLoading = false
        }
    }

    // MARK: Fetch + map + predict

    private func load(for location: CLLocation) async {
        do {
            let now = Date()
            let weather = try await weatherService.weather(for: location)
            let hours = weather.hourlyForecast.forecast
            let s24 = WeatherMapping.mapPoints(from: hours, start: now,
                                               end: now.addingTimeInterval(24 * 3600),
                                               location: location)
            let s10 = WeatherMapping.mapPoints(from: hours, start: now,
                                               end: now.addingTimeInterval(240 * 3600),
                                               location: location)
            let cur = WeatherMapping.mapCurrent(weather.currentWeather, location: location)

            series24h = s24
            series10d = s10
            current   = cur
            isLoading = false
            errorText = nil
            applyModel()      // colours + snapshot
        } catch {
            errorText = error.localizedDescription
            isLoading = false
        }
    }

    /// Re-apply the synced model to the already-fetched points (no refetch),
    /// then refresh the complication snapshot.
    func applyModel() {
        let state = WatchSyncReceiver.shared.payload?.regressionState
        let scenario = WatchSyncReceiver.shared.payload?.scenario ?? Scenario()
        func predicted(_ pts: [ForecastPoint]) -> [ForecastPoint] {
            pts.map { var p = $0; p.applyPrediction(state: state, scenario: scenario); return p }
        }
        series24h = predicted(series24h)
        series10d = predicted(series10d)
        if var c = current { c.applyPrediction(state: state, scenario: scenario); current = c }
        writeSnapshot()
    }

    // MARK: Complication snapshot

    private func writeSnapshot() {
        guard let cur = current else { return }
        let cal = Calendar.current
        let todayPoints = series24h.filter { cal.isDateInToday($0.date) }

        let temps = todayPoints.map { $0.temperatureC } + [cur.temperatureC]
        let tMin = temps.min() ?? cur.temperatureC
        let tMax = temps.max() ?? cur.temperatureC

        let hasModel = WatchSyncReceiver.shared.payload?.regressionState != nil
        let feels = todayPoints.compactMap { $0.myFeelsLikeScore } + [cur.myFeelsLikeScore].compactMap { $0 }
        let fMin = feels.min() ?? 0
        let fMax = feels.max() ?? 1000

        let snap = ComplicationSnapshot(
            updated: Date(),
            currentTempC: cur.temperatureC,
            useFahrenheit: WatchSyncReceiver.shared.payload?.useFahrenheit ?? false,
            hasModel: hasModel,
            todayTempMinC: tMin,
            todayTempMaxC: tMax,
            feelsMin: fMin,
            feelsMax: fMax,
            feelsCurrent: cur.myFeelsLikeScore ?? (fMin + fMax) / 2)
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()   // corner + circular
    }
}
