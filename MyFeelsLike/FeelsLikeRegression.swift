// SPDX-License-Identifier: GPL-3.0-or-later
//
//  FeelsLikeRegression.swift
//  MyFeelsLike
//
//  Personalized "feels like" model. Trained on the user's own ratings, used
//  to predict the purple curve / table column from forecast points.
//
//  Algorithm overview
//  ──────────────────
//   1. Each rating contributes one feature vector (apparent-temp anchor +
//      a fixed candidate set including humidity/wind/uv/etc + collinearity-
//      reduced temperature differences + ordinal self-report fields).
//   2. Feature vectors are z-scored over the rating set (mean/std saved
//      so inference can apply the same transform).
//   3. Forward stepwise selection: model M0 = [apparent]. For each
//      additional slot, exhaustively try every remaining candidate, fit
//      OLS (Cholesky on the normal equations), score by AICc. Add the
//      winner if AICc improves by ≥ 2 over the best smaller model.
//   4. Slot budget: k = max(0, (n - 5) / 5). The first slot opens at n=10
//      ratings (so the very first regression is intercept + apparent only).
//   5. Inference: standardize a forecast point's features the same way,
//      multiply by stored coefficients, get °C "feels like" prediction.
//
//  None of this lives on the main thread anyway — refits run on user
//  actions, not in tight loops.
//

import Foundation
import OSLog

private let fitLog = Logger(subsystem: "robotex.MyFeelsLike", category: "Regression")

// Feature, FeatureSource, Scenario, ForecastFeatureSource and RegressionState
// now live in FeelsLikeInference.swift (shared with the watch app). This file
// keeps the iOS-only training engine and the Rating feature conformance.

// MARK: - Feature extraction (training side: Rating → features)

extension Rating: PhysicalSource {
    func observation(_ v: PhysicalVar) -> Double {
        switch v {
        case .apparentC:  return apparentTemperatureC
        case .tempC:      return temperatureC
        case .wetBulbC:   return wetBulbC
        case .dewC:       return dewPointC
        case .humidity:   return humidity
        case .pressurePa: return stationPressurePa
        case .windKPH:    return windSpeedKPH
        case .uv:         return uvIndex
        case .precipProb: return precipProbability
        case .precipMM:   return precipitationMM
        case .cloud:      return cloudCover
        case .cloudLow:   return cloudCoverLow
        case .cloudMed:   return cloudCoverMedium
        case .cloudHigh:  return cloudCoverHigh
        case .activity:   return Double(activity)
        case .dress:      return Double(dress)
        case .sun:        return Double(sun)
        }
    }
}

extension Rating: FeatureSource {
    func value(for f: Feature) -> Double {
        switch f {
        case .apparentTempC:        return apparentTemperatureC
        case .apparentMinusTemp:    return apparentTemperatureC - temperatureC
        case .tempMinusWetBulb:     return temperatureC - wetBulbC
        case .wetBulbMinusDewPoint: return wetBulbC - dewPointC
        case .humidity:             return humidity
        case .stationPressurePa:    return stationPressurePa
        case .windSpeedKPH:         return windSpeedKPH
        case .precipProbability:    return precipProbability
        case .precipitationMM:      return precipitationMM
        case .cloudCover:           return cloudCover
        case .cloudCoverLow:        return cloudCoverLow
        case .cloudCoverMedium:     return cloudCoverMedium
        case .cloudCoverHigh:       return cloudCoverHigh
        case .uvIndex:              return uvIndex
        case .isDaylight:           return isDaylight ? 1 : 0
        case .activity:             return Double(activity)
        case .dress:                return Double(dress)
        case .sun:                  return Double(sun)
        // Hinges
        case .hinge_cold_10:        return max(0, 10 - apparentTemperatureC)
        case .hinge_warm_18:        return max(0, apparentTemperatureC - 18)
        case .hinge_hot_26:         return max(0, apparentTemperatureC - 26)
        case .hinge_wind_15:        return max(0, windSpeedKPH - 15)
        case .hinge_uv_4:           return max(0, uvIndex - 4)
        // Interactions
        case .ix_apparent_humidity: return apparentTemperatureC * humidity
        case .ix_apparent_uv:       return apparentTemperatureC * uvIndex
        case .ix_apparent_activity: return apparentTemperatureC * Double(activity)
        }
    }
}

// MARK: - The fit engine

enum FeelsLikeRegression {

    /// Minimum spread (out of 1000) of user-reported feels-like scores needed
    /// before a model is fit. Relaxed from 80 → 50 (5% of the color scale) so
    /// a model triggers with fewer varied ratings.
    static let minScoreSpread: Double = 50.0

    /// Minimum spread of apparent temperature (°C) across the ratings before a
    /// temperature response can be estimated at all. Rating only within a narrow
    /// band — e.g. eleven ratings taken during one heat wave, all between 28 and
    /// 32 °C — leaves the anchor's slope to absorb score differences that were
    /// really caused by sun/activity/clothing, producing an enormous (and often
    /// wrong-signed) °C coefficient that explodes outside that band.
    static let minApparentSpreadC: Double = 6.0

    /// Trigger threshold: at least 5 ratings, ≥ `minScoreSpread` spread of
    /// user-reported feels-like scores, and enough temperature variation to
    /// actually estimate a temperature response.
    /// Note there is deliberately *no* temperature-spread gate here. A narrow
    /// band of rated temperatures is handled where it actually matters: a
    /// feature needs 3 °C of spread to be eligible, the fitted model must still
    /// respond plausibly to temperature, and the range checks narrow the band
    /// outside the conditions that were rated. Gating here as well would deny a
    /// usable model to someone whose comfort really does vary with sun,
    /// activity or clothing within a narrow temperature range.
    static func canFit(ratings: [Rating]) -> Bool {
        guard ratings.count >= 5 else { return false }
        let ys = ratings.map { $0.feelsLikeScore }
        guard let lo = ys.min(), let hi = ys.max() else { return false }
        return (hi - lo) >= minScoreSpread
    }

    /// Observed spread of apparent temperature (°C) across the ratings.
    static func apparentSpread(_ ratings: [Rating]) -> Double {
        let ts = ratings.map { $0.apparentTemperatureC }
        guard let lo = ts.min(), let hi = ts.max() else { return 0 }
        return hi - lo
    }

    /// Total number of coefficients the ratings can support: one per five
    /// ratings. There is no mandatory anchor — apparentTempC competes for a slot
    /// like everything else, so someone who rated across a narrow temperature
    /// band can still get a useful model from sun/activity/clothing.
    static func featureBudget(n: Int) -> Int { max(0, n / 5) }

    /// Plain-language reasons a personalized model can't be fit yet (empty when
    /// one can). Used by the UI to explain the absence of personalized color.
    static func readinessReasons(ratings: [Rating]) -> [String] {
        let n = ratings.count
        if n < 5 {
            return ["You have \(n) of the 5 ratings needed to start a personalized model — keep rating how the weather feels."]
        }
        let ys = ratings.map { $0.feelsLikeScore }
        let spread = (ys.max() ?? 0) - (ys.min() ?? 0)
        if spread < minScoreSpread {
            let pct = max(1, Int((spread / 10).rounded()))
            let needPct = Int((minScoreSpread / 10).rounded())
            return ["Your \(n) ratings cover only about \(pct)% of the feels-like color range; at least ~\(needPct)% is needed. Rate some conditions that feel clearly cooler or warmer than the ones you've rated so far."]
        }
        if fit(ratings: ratings) == nil {
            // Give the most actionable reason. A narrow temperature band is the
            // usual root cause — it leaves nothing to separate the temperature's
            // effect from sun/activity/clothing — so mention it first.
            let tSpread = apparentSpread(ratings)
            if tSpread < minApparentSpreadC {
                return ["Your \(n) ratings span only about \(Int(tSpread.rounded())) °C, so the app can't yet tell how much of the difference came from the temperature rather than from sun, activity or clothing. Rate across a wider range of temperatures — clearly cooler or clearly warmer than you have so far."]
            }
            if let bad = rejection(ratings: ratings), case .coolerWhenWarmer = bad {
                return ["Your ratings so far say the weather feels *cooler* as it gets warmer, so a personalized color would be misleading. This usually means a few ratings were placed on the wrong end of the color scale — check your ratings, and rate a clearly hot moment and a clearly cold one."]
            }
            return ["Nothing in these \(n) ratings yet explains your comfort better than simply averaging them, so a personalized color would be guesswork. Rating across more varied weather should help."]
        }
        return []
    }

    /// Refit the model from scratch. Returns nil when the ratings can't support
    /// a believable model.
    ///
    /// Forward stepwise on AICc, but a candidate must *earn* its slot: at every
    /// step the model that would result is probed for physical sanity, so a
    /// feature that would make the model read cooler-when-warmer (or warmer in
    /// the wind, or cooler when more active) is simply not available at that
    /// step, and the next-best candidate can take the slot instead. That is
    /// strictly better than fitting first and rejecting afterwards, which threw
    /// away the whole model rather than the offending term.
    static func fit(ratings: [Rating]) -> RegressionState? {
        guard canFit(ratings: ratings) else { return nil }
        let n = ratings.count
        let budget = featureBudget(n: n)
        guard budget > 0 else { return nil }

        // No mandatory anchor: everything competes, including apparentTempC.
        // Pool is n-aware (hinges from 25, interactions from 40) and limited to
        // predictors that actually varied across the ratings.
        var remaining = Set(ModelPlausibility.eligible(Feature.allCases.filter { n >= $0.minimumN },
                                                       ratings: ratings))
        var selected: [Feature] = []
        // Baseline: the intercept-only model ("your comfort is just its average").
        // Starting from it means the ≥2 AICc margin applies to the *first*
        // feature too — a feature that barely beats predicting the mean has not
        // earned a slot, and picking the best of several near-tied weak
        // candidates would just be fitting noise.
        var bestState = fitOLS(ratings: ratings, features: [])

        for _ in 0..<budget {
            var bestNext: (Feature, RegressionState)? = nil
            for f in remaining {
                guard let st = fitOLS(ratings: ratings, features: selected + [f]) else { continue }
                // Eligibility at this step: the resulting model must be plausible.
                if let bad = ModelPlausibility.check(st, ratings: ratings) {
                    fitLog.debug("\(f.rawValue, privacy: .public) not eligible: \(bad.reason, privacy: .public)")
                    continue
                }
                if bestNext == nil || st.aicc < bestNext!.1.aicc { bestNext = (f, st) }
            }
            guard let pick = bestNext else { break }
            // Must beat the current model (starting from intercept-only) by 2.
            if let current = bestState, !(pick.1.aicc + 2.0 < current.aicc) { break }
            selected.append(pick.0)
            remaining.remove(pick.0)
            bestState = pick.1
        }

        // At least one coefficient, or there is no personal model to show (an
        // intercept-only fit would paint one flat color over every hour).
        guard var state = bestState, !selected.isEmpty else { return nil }
        attachRanges(&state, ratings: ratings)
        return state
    }

    /// Record the conditions the user actually rated in, so reliability can
    /// narrow the band outside them (see RegressionState.reliabilityWidth).
    private static func attachRanges(_ state: inout RegressionState, ratings: [Rating]) {
        var featureRanges: [String: RangeBox] = [:]
        for f in state.selectedFeatures {
            let vs = ratings.map { $0.value(for: f) }
            if let lo = vs.min(), let hi = vs.max() {
                featureRanges[f.rawValue] = RangeBox(lo: lo, hi: hi)
            }
        }
        var observationRanges: [String: RangeBox] = [:]
        for v in PhysicalVar.allCases {
            if let r = ModelPlausibility.range(v, in: ratings) {
                observationRanges[v.rawValue] = r
            }
        }
        let scores = ratings.map { $0.feelsLikeScore }
        state.featureRanges = featureRanges
        state.observationRanges = observationRanges
        if let lo = scores.min(), let hi = scores.max() {
            state.scoreRange = RangeBox(lo: lo, hi: hi)
        }
    }

    /// Why the fitted model was rejected as implausible, if it was. Used by the
    /// UI to explain the missing personal color instead of silently showing none.
    static func rejection(ratings: [Rating]) -> ModelPlausibility.Rejection? {
        guard canFit(ratings: ratings),
              let anchor = fitOLS(ratings: ratings, features: [.apparentTempC]) else { return nil }
        return ModelPlausibility.check(anchor, ratings: ratings)
    }

    /// Fit OLS for a specific feature set. Returns nil if X'X is singular.
    static func fitOLS(ratings: [Rating], features: [Feature]) -> RegressionState? {
        let n = ratings.count
        let p = features.count
        guard n > p + 1 else { return nil }

        // Build raw X (n × p) and y.
        var raw = Array(repeating: Array(repeating: 0.0, count: p), count: n)
        var y = Array(repeating: 0.0, count: n)
        for (i, r) in ratings.enumerated() {
            for (j, f) in features.enumerated() {
                raw[i][j] = r.value(for: f)
            }
            y[i] = r.feelsLikeScore
        }

        // Standardize columns.
        var means = Array(repeating: 0.0, count: p)
        var stds  = Array(repeating: 0.0, count: p)
        for j in 0..<p {
            let col = (0..<n).map { raw[$0][j] }
            let m = col.reduce(0, +) / Double(n)
            means[j] = m
            let v = col.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(n - 1)
            stds[j] = max(sqrt(v), 1e-9)
        }
        var Xstd = Array(repeating: Array(repeating: 0.0, count: p + 1), count: n)
        for i in 0..<n {
            Xstd[i][0] = 1.0  // intercept
            for j in 0..<p {
                Xstd[i][j + 1] = (raw[i][j] - means[j]) / stds[j]
            }
        }

        // Normal equations: (XᵀX) β = Xᵀy.  Symmetric positive definite.
        let m = p + 1
        var XtX = Array(repeating: Array(repeating: 0.0, count: m), count: m)
        var Xty = Array(repeating: 0.0, count: m)
        for i in 0..<n {
            for a in 0..<m {
                Xty[a] += Xstd[i][a] * y[i]
                for b in a..<m {
                    XtX[a][b] += Xstd[i][a] * Xstd[i][b]
                }
            }
        }
        for a in 0..<m {
            for b in 0..<a { XtX[a][b] = XtX[b][a] }
        }

        guard let L = cholesky(XtX) else { return nil }
        let beta = cholSolve(L: L, b: Xty)

        // Inverse of XtX via repeated solves on unit vectors — reused for
        // leverage at inference time.
        var inv = Array(repeating: Array(repeating: 0.0, count: m), count: m)
        for j in 0..<m {
            var e = Array(repeating: 0.0, count: m); e[j] = 1
            let col = cholSolve(L: L, b: e)
            for i in 0..<m { inv[i][j] = col[i] }
        }

        // Residuals → R² and AICc.
        var rss = 0.0
        for i in 0..<n {
            var yhat = 0.0
            for a in 0..<m { yhat += Xstd[i][a] * beta[a] }
            let r = y[i] - yhat
            rss += r * r
        }
        let yMean = y.reduce(0, +) / Double(n)
        let tss = y.reduce(0) { $0 + ($1 - yMean) * ($1 - yMean) }
        let r2 = tss > 1e-12 ? 1 - rss / tss : 0

        let nD = Double(n)
        let pD = Double(m)   // includes intercept
        // Guard rss=0 (perfect fit): use a tiny floor so log is finite.
        let rssSafe = max(rss, 1e-12)
        let aic = nD * log(rssSafe / nD) + 2.0 * pD
        // A finite penalty (not .infinity) so an over-parameterised fit is still
        // rejected by comparison, but the stored aicc stays JSON-encodable for
        // the CloudKit upload.
        let aicCorr = (nD - pD - 1 > 0) ? 2.0 * pD * (pD + 1) / (nD - pD - 1) : 1e12
        let aicc = aic + aicCorr

        return RegressionState(
            selectedFeatures: features,
            coefficients: beta,
            means: means,
            stds: stds,
            rSquared: r2,
            aicc: aicc,
            ratingCount: n,
            lastFitAt: Date(),
            invXtX: inv
        )
    }

    // MARK: - Cholesky on a symmetric positive-definite system

    /// Cholesky factor: returns lower-triangular L such that L L' = A.
    /// nil if A is not numerically positive-definite.
    static func cholesky(_ A: [[Double]]) -> [[Double]]? {
        let m = A.count
        var L = Array(repeating: Array(repeating: 0.0, count: m), count: m)
        for i in 0..<m {
            for j in 0...i {
                var sum = A[i][j]
                for k in 0..<j { sum -= L[i][k] * L[j][k] }
                if i == j {
                    if sum <= 1e-12 { return nil }
                    L[i][j] = sqrt(sum)
                } else {
                    L[i][j] = sum / L[j][j]
                }
            }
        }
        return L
    }

    /// Given Cholesky factor L (L L' = A), solve A x = b for x.
    static func cholSolve(L: [[Double]], b: [Double]) -> [Double] {
        let m = L.count
        // Forward solve L y = b
        var ysol = Array(repeating: 0.0, count: m)
        for i in 0..<m {
            var s = b[i]
            for k in 0..<i { s -= L[i][k] * ysol[k] }
            ysol[i] = s / L[i][i]
        }
        // Back solve Lᵀ x = y
        var x = Array(repeating: 0.0, count: m)
        for ii in 0..<m {
            let i = m - 1 - ii
            var s = ysol[i]
            for k in (i + 1)..<m { s -= L[k][i] * x[k] }
            x[i] = s / L[i][i]
        }
        return x
    }

    /// Convenience: one-shot Cholesky solve.  Kept for callers (and the
    /// regression unit tests) that don't need the factor itself.
    static func solveSPD(_ A: [[Double]], _ b: [Double]) -> [Double]? {
        guard let L = cholesky(A) else { return nil }
        return cholSolve(L: L, b: b)
    }
}

// MARK: - Persistence

enum RegressionStateStore {
    private static let key = "RegressionState_v1"

    static func load() -> RegressionState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RegressionState.self, from: data)
    }

    static func save(_ state: RegressionState?) {
        if let state, let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
