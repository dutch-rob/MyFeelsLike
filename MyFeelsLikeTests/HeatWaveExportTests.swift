// SPDX-License-Identifier: GPL-3.0-or-later
//
//  HeatWaveExportTests.swift
//  MyFeelsLikeTests
//
//  Regression test built from a real tester export (2026-07-31) whose model
//  showed a white — i.e. coldest — MyFeelsLike color during a heat wave.
//
//  The published model was:
//      apparentTempC   raw coef  -143.3 per °C     (wrong sign, huge)
//      cloudCoverLow   raw coef -8539.7 per unit   (observed range 0.01…0.07)
//  so an ordinary overcast forecast (cloudCoverLow ≈ 0.8) contributed roughly
//  −6800 points on a 0…1000 scale; the score clamps at 0, which renders white.
//
//  These ratings must no longer produce a published model.
//

import Testing
import Foundation
@testable import MyFeelsLike

struct HeatWaveExportTests {

    /// The 11 exported ratings, with the fields the model uses.
    private static let exported: [(t: Double, app: Double, wet: Double, dew: Double,
                                   hum: Double, wind: Double, uv: Double,
                                   cloud: Double, cloudLow: Double,
                                   act: Int, dress: Int, sun: Int, score: Double)] = [
        (30.76, 32.16874, 22.99979, 19.77489, 0.52, 13.68, 8, 0.02, 0.03, 1, 1, -1, 629.4838),
        (30.76, 32.16874, 22.99979, 19.77489, 0.52, 13.68, 8, 0.02, 0.03, 1, 1,  1, 864.1732),
        (30.76, 32.16874, 22.99979, 19.77489, 0.52, 13.68, 8, 0.02, 0.03, 1, 1,  0, 874.6719),
        (30.41, 31.87675, 22.52025, 19.14043, 0.51, 14.17, 6, 0.02, 0.02, 1, 1, -1, 804.4619),
        (30.76, 30.75380, 17.77463, 10.68146, 0.29, 13.23, 7, 0.46, 0.01, 0, 2,  1, 1000.0),
        (25.40, 28.29810, 20.27240, 17.84621, 0.63,  3.96, 6, 0.08, 0.07, 1, 2,  0, 1000.0),
        (29.66, 30.80240, 21.89800, 18.45088, 0.51, 12.34, 10, 0.02, 0.03, 0, 2, 0, 694.2257),
        (30.01, 32.16894, 22.00419, 18.45619, 0.50,  7.50, 8, 0.04, 0.04, 0, 1, -1, 508.7489),
        (30.01, 32.16894, 22.00419, 18.45619, 0.50,  7.50, 8, 0.04, 0.04, 0, 1,  0, 498.0315),
        (29.76, 30.80831, 22.35679, 19.15874, 0.53, 13.27, 9, 0.06, 0.06, 1, 1,  1, 667.7603),
        (29.76, 30.80831, 22.35679, 19.15874, 0.53, 13.27, 9, 0.06, 0.06, 0, 1,  0, 412.7297),
    ]

    private func ratings() -> [Rating] {
        Self.exported.map { r in
            let p = mkForecastPoint(tempC: r.t, apparentC: r.app, wetBulbC: r.wet, dewC: r.dew,
                                    humidity: r.hum, windKPH: r.wind, uv: r.uv,
                                    cloud: r.cloud, cloudLow: r.cloudLow, stationPa: 100_800)
            return Rating(feelsLikeScore: r.score, activity: r.act, dress: r.dress,
                          sun: r.sun, snapshot: p)
        }
    }

    /// The bottom line: these ratings must not yield a published model, so the
    /// app falls back to the generic forecast instead of painting a heat wave
    /// white.
    @Test func realHeatWaveExportProducesNoModel() {
        // Nothing in these ratings beats simply averaging them by the AICc
        // margin, so no personal model is published.
        #expect(FeelsLikeRegression.fit(ratings: ratings()) == nil)
    }

    /// Cause 1: cloudCoverLow only ever ranged 0.01…0.07, so standardising it
    /// turned noise into a −8539-per-unit coefficient that dominates any real
    /// forecast. It must not be an eligible predictor.
    @Test func lowCloudWasTooConstantToBeAPredictor() {
        let rs = ratings()
        #expect(ModelPlausibility.spread(.cloudCoverLow, in: rs) < 0.07)
        #expect(!ModelPlausibility.eligible([.cloudCoverLow], ratings: rs).contains(.cloudCoverLow))
    }

    /// Cause 2: every rating came from one heat wave — under 4 °C apart. That no
    /// longer blocks a model outright; instead apparentTempC can't earn a slot
    /// (its response would be wrong-signed), and the not-in-model range check
    /// narrows the band once the forecast leaves that band.
    @Test func allRatingsCameFromOneNarrowTemperatureBand() {
        #expect(FeelsLikeRegression.apparentSpread(ratings()) < 4.0)
    }

    /// Temperature must not win a slot on this data.
    @Test func temperatureCannotEarnASlot() {
        let rs = ratings()
        guard let state = FeelsLikeRegression.fit(ratings: rs) else { return }  // no model is also fine
        #expect(!state.selectedFeatures.contains(.apparentTempC))
    }

    /// And the advice names the root cause: everything was rated in one band.
    @Test func testerIsToldToRateAcrossMoreTemperatures() {
        let reasons = FeelsLikeRegression.readinessReasons(ratings: ratings())
        #expect(reasons.count == 1)
        #expect(reasons[0].contains("wider range"))
    }

    /// The published model's own numbers, re-checked through the guardrail: a
    /// −143/°C response is both the wrong sign and far too steep.
    @Test func theShippedCoefficientsWouldBeRejected() {
        let rs = ratings()
        // Rebuild the model as exported: apparentTempC + cloudCoverLow.
        guard let bad = FeelsLikeRegression.fitOLS(ratings: rs,
                                                   features: [.apparentTempC, .cloudCoverLow]) else {
            Issue.record("expected the exported feature set to fit"); return
        }
        guard let rejection = ModelPlausibility.check(bad, ratings: rs) else {
            Issue.record("the exported model should have been rejected"); return
        }
        switch rejection {
        case .coolerWhenWarmer, .temperatureResponseTooSteep: break   // either is correct
        default: Issue.record("unexpected rejection: \(rejection)")
        }
    }
}
