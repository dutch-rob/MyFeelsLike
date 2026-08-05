// SPDX-License-Identifier: GPL-3.0-or-later
//
//  ModelPlausibilityTests.swift
//  MyFeelsLikeTests
//
//  The guardrails that keep a personal model physically believable: a model
//  that says "warmer feels colder" must not be published, and predictors the
//  user never saw vary must not enter the model.
//

import Testing
import Foundation
@testable import MyFeelsLike

struct ModelPlausibilityTests {

    /// A rating whose whole temperature family moves together (so differences
    /// stay realistic), with optional cloud cover.
    private func rating(apparent: Double, score: Double, cloud: Double = 0.3,
                        wind: Double = 5, activity: Int = 1) -> Rating {
        Rating(feelsLikeScore: score, activity: activity, dress: 0, sun: 0,
               snapshot: mkForecastPoint(tempC: apparent + 1, apparentC: apparent,
                                         wetBulbC: apparent - 3, dewC: apparent - 6,
                                         humidity: 0.55, windKPH: wind, uv: 3,
                                         cloud: cloud))
    }

    /// Sensible ratings: hotter weather rated hotter.
    private func sensibleRatings() -> [Rating] {
        stride(from: 0.0, through: 35.0, by: 2.5).map {
            rating(apparent: $0, score: 150 + 20 * $0)     // 20 points per °C
        }
    }

    /// The failing tester's shape: hotter weather rated *colder*.
    private func invertedRatings() -> [Rating] {
        stride(from: 0.0, through: 35.0, by: 2.5).map {
            rating(apparent: $0, score: 850 - 20 * $0)
        }
    }

    @Test func sensibleRatingsProduceAModel() {
        let state = FeelsLikeRegression.fit(ratings: sensibleRatings())
        #expect(state != nil)
        #expect(ModelPlausibility.check(state!, ratings: sensibleRatings()) == nil)
    }

    @Test func warmerMustNotPredictCooler() {
        // The core guardrail: rather than publishing a confidently wrong model
        // (which is what showed a white/cold color during a heat wave), publish
        // nothing and let the app fall back to the generic forecast.
        let ratings = invertedRatings()
        #expect(FeelsLikeRegression.fit(ratings: ratings) == nil)

        guard let bad = FeelsLikeRegression.rejection(ratings: ratings) else {
            Issue.record("expected a rejection"); return
        }
        guard case .coolerWhenWarmer = bad else {
            Issue.record("expected coolerWhenWarmer, got \(bad)"); return
        }
    }

    @Test func rejectionIsExplainedToTheUser() {
        let reasons = FeelsLikeRegression.readinessReasons(ratings: invertedRatings())
        #expect(reasons.count == 1)
        #expect(reasons[0].contains("cooler"))
    }

    /// The tester's cloud cover ran 0.00…0.07. Standardising a near-constant
    /// predictor turns noise into a huge coefficient that explodes when the
    /// forecast leaves that range, so it must not be eligible at all.
    @Test func nearConstantPredictorsAreNotEligible() {
        let flatCloud = stride(from: 0.0, through: 35.0, by: 2.5).enumerated().map { i, t in
            rating(apparent: t, score: 150 + 20 * t, cloud: Double(i % 2) * 0.07)
        }
        let eligible = ModelPlausibility.eligible([.cloudCover, .windSpeedKPH], ratings: flatCloud)
        #expect(!eligible.contains(.cloudCover))

        let variedCloud = stride(from: 0.0, through: 35.0, by: 2.5).enumerated().map { i, t in
            rating(apparent: t, score: 150 + 20 * t, cloud: Double(i % 2) * 0.9)
        }
        #expect(ModelPlausibility.eligible([.cloudCover], ratings: variedCloud).contains(.cloudCover))
    }

    /// A believable model responds to temperature at a believable rate — the
    /// check is in score-per-°C, not in the stored (per-standard-deviation)
    /// coefficients, which aren't comparable across features.
    @Test func temperatureResponseIsWithinPlausibleRange() {
        let ratings = sensibleRatings()
        guard let state = FeelsLikeRegression.fit(ratings: ratings) else {
            Issue.record("expected a model"); return
        }
        let base = ModelPlausibility.medianVector(ratings)
        let perDegree = (state.predict(base.warmed(by: 3)) - state.predict(base.warmed(by: -3))) / 6
        #expect(perDegree > ModelPlausibility.minScorePerDegreeC)
        #expect(perDegree < ModelPlausibility.maxScorePerDegreeC)
        #expect(abs(perDegree - 20) < 5)   // recovers the ~20 points/°C we planted
    }

    /// Raising every temperature together must leave the difference features
    /// alone — otherwise the probe would silently be changing humidity too.
    @Test func warmingKeepsTemperatureDifferences() {
        let v = PhysicalVector()
        let w = v.warmed(by: 5)
        #expect(abs(w.value(for: .apparentMinusTemp) - v.value(for: .apparentMinusTemp)) < 1e-9)
        #expect(abs(w.value(for: .tempMinusWetBulb) - v.value(for: .tempMinusWetBulb)) < 1e-9)
        #expect(abs(w.value(for: .wetBulbMinusDewPoint) - v.value(for: .wetBulbMinusDewPoint)) < 1e-9)
        #expect(abs(w.value(for: .apparentTempC) - (v.value(for: .apparentTempC) + 5)) < 1e-9)
    }

    /// PhysicalVector must extract features identically to a real Rating,
    /// otherwise the probe would be testing a different model than we fit.
    @Test func physicalVectorMatchesRatingExtraction() {
        let r = rating(apparent: 22, score: 600, cloud: 0.4, wind: 12, activity: 2)
        let v = PhysicalVector(tempC: 23, apparentC: 22, wetBulbC: 19, dewC: 16,
                               humidity: 0.55, pressurePa: 100_000, windKPH: 12,
                               precipProb: 0, precipMM: 0, cloud: 0.4,
                               cloudLow: 0, cloudMed: 0, cloudHigh: 0, uv: 3,
                               daylight: 1, activity: 2, dress: 0, sun: 0)
        for f in Feature.allCases {
            #expect(abs(v.value(for: f) - r.value(for: f)) < 1e-6, "mismatch for \(f)")
        }
    }
}
