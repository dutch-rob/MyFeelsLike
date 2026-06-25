//
//  PsychrometryTests.swift
//  MyFeelsLikeTests
//
//  satPress is the saturation VAPOUR pressure (a function of temperature only).
//  Wet-bulb tests use realistic station pressures (~100 kPa, plus a high-
//  altitude ~50 kPa case) — never unrealistic ones.
//

import Testing
import Foundation
@testable import MyFeelsLike

struct PsychrometryTests {

    @Test func satPressIncreasesWithTemperature() {
        #expect(PsychrometryCalculator.satPress(10) > PsychrometryCalculator.satPress(0))
        #expect(PsychrometryCalculator.satPress(30) > PsychrometryCalculator.satPress(20))
    }

    @Test func satPressAtFreezingIsKnownConstant() {
        // satPress is in kPa; saturation vapour pressure at 0 °C ≈ 0.611 kPa.
        #expect(abs(PsychrometryCalculator.satPress(0) - 0.6113) < 0.02)
    }

    @Test func wetBulbNeverExceedsDryBulbAtRealisticPressures() {
        for pressure in [100_000.0, 50_000.0] {
            for dry in [-5.0, 5, 15, 25, 35] {
                let wb = PsychrometryCalculator.psychC(
                    pressurePa: pressure, dryBulbCelsius: dry, relativeHumidity: 0.5)
                #expect(wb <= dry + 1e-6)
            }
        }
    }

    @Test func wetBulbEqualsDryBulbAtSaturation() {
        let dry = 22.0
        let wb = PsychrometryCalculator.psychC(
            pressurePa: 100_000, dryBulbCelsius: dry, relativeHumidity: 1.0)
        #expect(abs(wb - dry) < 0.5)
    }

    @Test func celsiusAndFahrenheitWetBulbAgree() {
        let pressure = 100_000.0, dryC = 18.0, rh = 0.6
        let wbC = PsychrometryCalculator.psychC(
            pressurePa: pressure, dryBulbCelsius: dryC, relativeHumidity: rh)
        let wbF = PsychrometryCalculator.psychF(
            pressurePa: pressure, dryBulbFahrenheit: dryC * 9/5 + 32, relativeHumidity: rh)
        #expect(abs(wbF - (wbC * 9/5 + 32)) < 0.5)
    }
}
