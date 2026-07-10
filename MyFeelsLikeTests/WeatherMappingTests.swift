// SPDX-License-Identifier: GPL-3.0-or-later
//
//  WeatherMappingTests.swift
//  MyFeelsLikeTests
//
//  The pure `derived` helper (station pressure + wet bulb). The full
//  mapPoints/mapCurrent need WeatherKit types that can't be built in tests,
//  so they're intentionally not covered.
//

import Testing
import Foundation
import CoreLocation
@testable import MyFeelsLike

struct WeatherMappingTests {

    @Test func derivedAtSeaLevelKeepsPressureAndSaneWetBulb() {
        let seaLevel = CLLocation(latitude: 0, longitude: 0)   // altitude 0
        let d = WeatherMapping.derived(
            seaLevelPa: 101_325, tempF: 77, tempC: 25, rh: 0.5, location: seaLevel)
        #expect(abs(d.stationPa - 101_325) < 50)   // altitude 0 → station ≈ sea level
        #expect(d.wetC <= 25 + 1e-6)               // wet bulb ≤ dry bulb
        #expect(abs(d.wetF - (d.wetC * 9/5 + 32)) < 0.5)
    }

    @Test func derivedAtAltitudeLowersStationPressure() {
        let high = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            altitude: 2000, horizontalAccuracy: 1, verticalAccuracy: 1, timestamp: Date())
        let d = WeatherMapping.derived(
            seaLevelPa: 101_325, tempF: 50, tempC: 10, rh: 0.5, location: high)
        #expect(d.stationPa < 101_325)             // higher altitude → lower pressure
    }
}
