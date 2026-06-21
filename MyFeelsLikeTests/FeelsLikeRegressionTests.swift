//
//  FeelsLikeRegressionTests.swift
//  MyFeelsLikeTests
//

import Testing
import Foundation
@testable import MyFeelsLike

/// In-memory feature source used to test fit + predict without touching SwiftData.
private struct StubFeatures: FeatureSource {
    var values: [Feature: Double] = [:]
    func value(for f: Feature) -> Double { values[f] ?? 0 }
}

/// Build a synthetic Rating with selected feature values.  All other fields
/// default to zero, which is fine because we control which features the
/// regression considers (and z-scoring of constant columns is clamped).
private func mkRating(apparent: Double, humidity: Double, wind: Double, feelsLike: Double) -> Rating {
    let snap = ForecastPoint(
        date: Date(),
        symbolName: "sun.max",
        isDaylight: true,
        uvIndex: 0,
        temperatureF: 0, temperatureC: 0,
        apparentTemperatureF: 0, apparentTemperatureC: apparent,
        wetBulbF: 0, wetBulbC: 0,
        dewPointF: 0, dewPointC: 0,
        precipProbability: 0, precipitationMM: 0,
        windSpeedMPH: 0, windSpeedKPH: wind,
        cloudCover: 0,
        cloudCoverLow: 0, cloudCoverMedium: 0, cloudCoverHigh: 0,
        humidity: humidity, stationPressurePa: 100000,
        myFeelsLikeC: nil, myFeelsLikeF: nil
    )
    return Rating(
        feelsLikeC: feelsLike,
        activity: 1, dress: 0, sun: 0,
        snapshot: snap
    )
}

struct FeelsLikeRegressionTests {

    // MARK: Cholesky solver basics

    @Test func solvesIdentitySystem() {
        let A = [[1.0, 0, 0], [0, 1.0, 0], [0, 0, 1.0]]
        let b = [3.0, -1.0, 7.0]
        let x = FeelsLikeRegression.solveSPD(A, b)!
        #expect(abs(x[0] - 3) < 1e-9)
        #expect(abs(x[1] + 1) < 1e-9)
        #expect(abs(x[2] - 7) < 1e-9)
    }

    @Test func solvesGeneralSPDSystem() {
        // A = LLᵀ where L = [[2,0],[1,3]]; A = [[4,2],[2,10]]
        // A · [2, 2] = [4·2+2·2, 2·2+10·2] = [12, 24]  → x = [2, 2]
        let A = [[4.0, 2.0], [2.0, 10.0]]
        let b = [12.0, 24.0]
        let x = FeelsLikeRegression.solveSPD(A, b)!
        #expect(abs(x[0] - 2) < 1e-9)
        #expect(abs(x[1] - 2) < 1e-9)
    }

    // MARK: Trigger condition

    @Test func canFitRequires5RatingsAnd5DegreeSpread() {
        // 4 ratings → no.
        let r4 = (0..<4).map { _ in mkRating(apparent: 20, humidity: 0.5, wind: 5, feelsLike: 20) }
        #expect(!FeelsLikeRegression.canFit(ratings: r4))

        // 5 ratings, all same value → spread = 0 → no.
        let r5flat = (0..<5).map { _ in mkRating(apparent: 20, humidity: 0.5, wind: 5, feelsLike: 20) }
        #expect(!FeelsLikeRegression.canFit(ratings: r5flat))

        // 5 ratings, spread = 5 exactly → yes.
        var r5 = r5flat
        r5[0] = mkRating(apparent: 15, humidity: 0.5, wind: 5, feelsLike: 15)
        r5[4] = mkRating(apparent: 25, humidity: 0.5, wind: 5, feelsLike: 20)
        #expect(FeelsLikeRegression.canFit(ratings: r5))
    }

    // MARK: Budget

    @Test func featureBudgetMatchesSpec() {
        #expect(FeelsLikeRegression.featureBudget(n: 4) == 0)
        #expect(FeelsLikeRegression.featureBudget(n: 5) == 0)
        #expect(FeelsLikeRegression.featureBudget(n: 9) == 0)
        #expect(FeelsLikeRegression.featureBudget(n: 10) == 1)
        #expect(FeelsLikeRegression.featureBudget(n: 14) == 1)
        #expect(FeelsLikeRegression.featureBudget(n: 15) == 2)
        #expect(FeelsLikeRegression.featureBudget(n: 20) == 3)
    }

    // MARK: Fit recovers a known relationship

    @Test func recoversSlopeOfApparentTempOnly() {
        // y = 0.7 * apparent + 6 + tiny noise
        // n=8 ratings, k budget = 0, so model is intercept + apparent only.
        let apparents = [10.0, 12, 15, 18, 22, 25, 28, 30]
        let ys = apparents.map { 0.7 * $0 + 6 }
        let ratings = zip(apparents, ys).map { (a, y) in
            mkRating(apparent: a, humidity: 0.5, wind: 5, feelsLike: y)
        }
        let state = FeelsLikeRegression.fit(ratings: ratings)!
        #expect(state.selectedFeatures == [.apparentTempC])

        // Predict at apparent = 20 → expected 0.7*20 + 6 = 20.
        let pred = state.predict(StubFeatures(values: [.apparentTempC: 20]))
        #expect(abs(pred - 20.0) < 0.01)
    }

    @Test func picksTheTrulyExtraneousVariable() {
        // y = apparent + 2*wind  (n=12, budget allows 1 extra feature).
        // wind should be selected over humidity.
        let apparents: [Double] = [10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32]
        let winds:     [Double] = [ 1,  3,  2,  6,  4,  8,  5, 10,  7, 12, 11, 14]
        let humids:    [Double] = [0.4, 0.7, 0.5, 0.3, 0.6, 0.8, 0.4, 0.5, 0.6, 0.7, 0.5, 0.4]
        let ratings = (0..<12).map { i in
            mkRating(apparent: apparents[i],
                     humidity: humids[i],
                     wind: winds[i],
                     feelsLike: apparents[i] + 2 * winds[i])
        }
        let state = FeelsLikeRegression.fit(ratings: ratings)!
        #expect(state.selectedFeatures.contains(.windSpeedKPH))
        #expect(!state.selectedFeatures.contains(.humidity))
        #expect(state.rSquared > 0.99)
    }
}
