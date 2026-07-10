// SPDX-License-Identifier: GPL-3.0-or-later
//
//  InferenceTests.swift
//  MyFeelsLikeTests
//
//  Feature gating, feature extraction, prediction and leverage/opacity.
//

import Testing
import Foundation
@testable import MyFeelsLike

struct InferenceTests {

    @Test func candidatesGateBySampleSize() {
        let small = Feature.candidates(for: 10)
        #expect(!small.contains(.apparentTempC))   // anchor is never a candidate
        #expect(!small.contains(.hinge_hot_26))    // hinges unlock at 25
        #expect(!small.contains(.ix_apparent_uv))  // interactions unlock at 40

        let mid = Feature.candidates(for: 25)
        #expect(mid.contains(.hinge_hot_26))
        #expect(!mid.contains(.ix_apparent_uv))

        let big = Feature.candidates(for: 40)
        #expect(big.contains(.hinge_hot_26))
        #expect(big.contains(.ix_apparent_uv))
    }

    @Test func featureSourceExtractsExpectedValues() {
        let p = mkForecastPoint(tempC: 20, apparentC: 18, wetBulbC: 14, dewC: 10,
                                humidity: 0.6, windKPH: 25, uv: 7)
        let src = ForecastFeatureSource(p: p, scenario: Scenario(activity: 2, dress: 1, sun: -1))
        #expect(src.value(for: .apparentTempC) == 18)
        #expect(abs(src.value(for: .apparentMinusTemp) - (18 - 20)) < 1e-9)
        #expect(abs(src.value(for: .tempMinusWetBulb) - (20 - 14)) < 1e-9)
        #expect(src.value(for: .windSpeedKPH) == 25)
        #expect(src.value(for: .activity) == 2)
        #expect(src.value(for: .sun) == -1)
        #expect(abs(src.value(for: .hinge_wind_15) - 10) < 1e-9)   // max(0, 25-15)
        #expect(abs(src.value(for: .hinge_uv_4) - 3) < 1e-9)       // max(0, 7-4)
        #expect(abs(src.value(for: .ix_apparent_uv) - (18 * 7)) < 1e-9)
    }

    @Test func predictReproducesFittedLineAndOpacityFadesWithDistance() {
        // score = 8·apparent + 100  (spread 160 over apparent 10…30).
        let apparents = [10.0, 14, 18, 22, 26, 30]
        let ratings = apparents.map { mkRating(apparent: $0, feelsLike: 8 * $0 + 100) }
        let state = FeelsLikeRegression.fit(ratings: ratings)!

        let inSample = StubFeatures(values: [.apparentTempC: 22])   // a training point
        #expect(abs(state.predict(inSample) - (8 * 22 + 100)) < 0.5)

        if let h = state.leverage(inSample) {
            #expect(h >= 0 && h <= 1.0001)   // hat-diagonal of a training point
        }
        #expect(state.predictionOpacity(inSample) > 0.99)           // in distribution

        let farOut = StubFeatures(values: [.apparentTempC: 200])    // way outside 10…30
        #expect(state.predictionOpacity(farOut) < state.predictionOpacity(inSample))
    }
}
