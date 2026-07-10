// SPDX-License-Identifier: GPL-3.0-or-later
//
//  FeelsLikeRegressionTests.swift
//  MyFeelsLikeTests
//
//  Solver + training-trigger + feature-selection behavior of the regression.
//  Helpers (StubFeatures / mkRating) live in TestSupport.swift.
//

import Testing
import Foundation
@testable import MyFeelsLike

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
        // A = LLᵀ with L = [[2,0],[1,3]] → A = [[4,2],[2,10]]; A·[2,2] = [12,24].
        let A = [[4.0, 2.0], [2.0, 10.0]]
        let b = [12.0, 24.0]
        let x = FeelsLikeRegression.solveSPD(A, b)!
        #expect(abs(x[0] - 2) < 1e-9)
        #expect(abs(x[1] - 2) < 1e-9)
    }

    // MARK: Trigger condition (needs ≥5 ratings and ≥80 score-units of spread)

    @Test func canFitRequires5RatingsAndScoreSpread() {
        // 4 ratings → no.
        let r4 = (0..<4).map { _ in mkRating(apparent: 20, feelsLike: 500) }
        #expect(!FeelsLikeRegression.canFit(ratings: r4))

        // 5 ratings, all identical → spread 0 → no.
        let flat = (0..<5).map { _ in mkRating(apparent: 20, feelsLike: 500) }
        #expect(!FeelsLikeRegression.canFit(ratings: flat))

        // 5 ratings, spread exactly 80 → yes.
        var ok = flat
        ok[0] = mkRating(apparent: 15, feelsLike: 460)
        ok[4] = mkRating(apparent: 25, feelsLike: 540)   // 540 − 460 = 80
        #expect(FeelsLikeRegression.canFit(ratings: ok))
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
        // score = 8·apparent + 100  (apparent 10…30 → spread 160 ≥ 80).
        // n = 8 → budget 0, so the model is intercept + apparentTempC only.
        let apparents = [10.0, 12, 15, 18, 22, 25, 28, 30]
        let ratings = apparents.map { a in
            mkRating(apparent: a, feelsLike: 8 * a + 100)
        }
        let state = FeelsLikeRegression.fit(ratings: ratings)!
        #expect(state.selectedFeatures == [.apparentTempC])

        // Predict at apparent = 20 → 8·20 + 100 = 260.
        let pred = state.predict(StubFeatures(values: [.apparentTempC: 20]))
        #expect(abs(pred - 260) < 0.01)
    }

    @Test func picksTheTrulyExtraneousVariable() {
        // score = 5·apparent + 10·wind  (n = 12 → budget 1).
        // Wind, the real second predictor, should be chosen over humidity.
        let apparents: [Double] = [10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32]
        let winds:     [Double] = [ 1,  3,  2,  6,  4,  8,  5, 10,  7, 12, 11, 14]
        let humids:    [Double] = [0.4, 0.7, 0.5, 0.3, 0.6, 0.8, 0.4, 0.5, 0.6, 0.7, 0.5, 0.4]
        let ratings = (0..<12).map { i in
            mkRating(apparent: apparents[i], humidity: humids[i], wind: winds[i],
                     feelsLike: 5 * apparents[i] + 10 * winds[i])
        }
        let state = FeelsLikeRegression.fit(ratings: ratings)!
        #expect(state.selectedFeatures.contains(.windSpeedKPH))
        #expect(!state.selectedFeatures.contains(.humidity))
        #expect(state.rSquared > 0.99)
    }
}
