//
//  CodableRoundTripTests.swift
//  MyFeelsLikeTests
//
//  Types that cross WatchConnectivity / the App Group must survive
//  encode → decode unchanged, or the watch silently shows stale/empty data.
//

import Testing
import Foundation
@testable import MyFeelsLike

struct CodableRoundTripTests {

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @Test func regressionStateRoundTrips() throws {
        let s = RegressionState(
            selectedFeatures: [.apparentTempC, .windSpeedKPH],
            coefficients: [1, 2, 3], means: [10, 20], stds: [1, 2],
            rSquared: 0.9, aicc: 12.3, ratingCount: 7,
            lastFitAt: Date(timeIntervalSince1970: 1000),
            invXtX: [[1, 0, 0], [0, 1, 0], [0, 0, 1]])
        let back = try roundTrip(s)
        #expect(back.selectedFeatures == s.selectedFeatures)
        #expect(back.coefficients == s.coefficients)
        #expect(back.means == s.means)
        #expect(back.stds == s.stds)
        #expect(back.ratingCount == s.ratingCount)
        #expect(back.invXtX?.count == 3)
    }

    @Test func watchSyncPayloadRoundTrips() throws {
        let payload = WatchSyncPayload(
            regressionState: nil, useFahrenheit: true,
            scenarioActivity: 2, scenarioDress: -1, scenarioSun: 1,
            places: [PlaceDTO(id: UUID(), name: "Home", latitude: 1, longitude: 2, altitude: 3)])
        let back = try roundTrip(payload)
        #expect(back.useFahrenheit == true)
        #expect(back.scenarioActivity == 2)
        #expect(back.scenarioDress == -1)
        #expect(back.scenarioSun == 1)
        #expect(back.places.first?.name == "Home")
        #expect(back.places.first?.altitude == 3)
    }

    @Test func complicationSnapshotRoundTrips() throws {
        let frame = ComplicationFrame(
            date: Date(timeIntervalSince1970: 500),
            currentTempC: 21, feelsCurrent: 500, feelsMin: 200, feelsMax: 800,
            todayTempMinC: 15, todayTempMaxC: 27)
        let snap = ComplicationSnapshot(
            updated: Date(timeIntervalSince1970: 1),
            useFahrenheit: false, hasModel: true, frames: [frame])
        let back = try roundTrip(snap)
        #expect(back.frames.count == 1)
        #expect(back.frames[0].feelsMax == 800)
        #expect(back.hasModel == true)
    }
}
