// SPDX-License-Identifier: GPL-3.0-or-later
//
//  FeelsLikeInference.swift
//  MyFeelsLike
//
//  Inference half of the personalized "feels like" model: the feature
//  definitions, the feature-source protocol, the inference scenario, the
//  forecast-point feature source, and the persistable RegressionState with
//  predict / leverage / opacity. Pure value types with no SwiftData or UI
//  dependency, so this compiles on the watch app and widget too.
//
//  Training (fit / OLS / Rating conformance / UserDefaults persistence) lives
//  in FeelsLikeRegression.swift and stays iOS-only.
//

import Foundation

// MARK: - Feature definitions

/// Every regressor the model knows about.  Order matters only for stable
/// serialization; selection is by name.
enum Feature: String, CaseIterable, Codable {
    /// The anchor — always included.
    case apparentTempC

    // Collinearity-reduced temperature relatives.
    case apparentMinusTemp        // apparent − temperature   (wind/RH correction)
    case tempMinusWetBulb         // wet-bulb depression
    case wetBulbMinusDewPoint     // humidity gap

    // Other weather variables.
    case humidity
    case stationPressurePa
    case windSpeedKPH
    case precipProbability
    case precipitationMM
    case cloudCover
    case cloudCoverLow
    case cloudCoverMedium
    case cloudCoverHigh
    case uvIndex
    case isDaylight               // 0 / 1

    // Self-report (ordinal).
    case activity                 // 0…3
    case dress                    // -2…+2
    case sun                      // -1…+1

    // Piecewise-linear hinge terms (candidates from n ≥ 25).
    // Each is max(0, x − h) or max(0, h − x), giving a slope change at h.
    case hinge_cold_10     // max(0, 10 − apparentTempC)  — cold amplification below 10 °C
    case hinge_warm_18     // max(0, apparentTempC − 18)  — warm onset above 18 °C
    case hinge_hot_26      // max(0, apparentTempC − 26)  — heat amplification above 26 °C
    case hinge_wind_15     // max(0, windSpeedKPH − 15)   — noticeable wind threshold
    case hinge_uv_4        // max(0, uvIndex − 4)         — moderate UV threshold

    // Interaction terms (candidates from n ≥ 40).
    case ix_apparent_humidity   // apparentTempC × humidity
    case ix_apparent_uv         // apparentTempC × uvIndex
    case ix_apparent_activity   // apparentTempC × activity

    /// Minimum number of ratings before this feature becomes a stepwise candidate.
    var minimumN: Int {
        switch self {
        case .hinge_cold_10, .hinge_warm_18, .hinge_hot_26,
             .hinge_wind_15, .hinge_uv_4:
            return 25
        case .ix_apparent_humidity, .ix_apparent_uv, .ix_apparent_activity:
            return 40
        default:
            return 0
        }
    }

    /// All features eligible as stepwise candidates for a given sample size.
    /// Excludes the anchor (apparentTempC) and any feature whose minimumN > n.
    static func candidates(for n: Int) -> [Feature] {
        allCases.filter { $0 != .apparentTempC && n >= $0.minimumN }
    }
}

// MARK: - Feature extraction

protocol FeatureSource {
    func value(for f: Feature) -> Double
}

// MARK: - Physical observations and the model rule table

/// The raw observations behind a rating/forecast. Distinct from `Feature`:
/// several of these (tempC, wetBulbC, dewC) are never model features on their
/// own — temperature enters through apparentC and the collinearity-reduced
/// differences — but every one of them is still checked for "is the forecast
/// inside the range this user actually rated in?".
///
/// `isDaylight` is deliberately absent: it is binary, and almost everyone rates
/// only in daylight at first, so range-checking it would leave every new user
/// with a permanently narrow band all night.
enum PhysicalVar: String, CaseIterable, Codable {
    case apparentC, tempC, wetBulbC, dewC
    case humidity, pressurePa, windKPH, uv
    case precipProb, precipMM
    case cloud, cloudLow, cloudMed, cloudHigh
    case activity, dress, sun

    /// How far outside the rated range (in range-lengths) the forecast may sit
    /// before the band is fully narrowed, when this variable is *not* in the model.
    var notInModelFactor: Double {
        switch self {
        case .apparentC, .tempC, .wetBulbC, .dewC: return 1.5
        case .humidity, .windKPH, .uv:             return 2
        case .sun, .activity, .dress:              return 1
        case .precipMM, .precipProb, .cloud, .cloudHigh, .cloudLow, .cloudMed,
             .pressurePa:                          return 4
        }
    }

    /// Floor for the range length used as the yardstick. Without it a variable
    /// the user never saw vary (e.g. no rain in any rating) would have a
    /// zero-length range, making any non-zero forecast infinitely far outside.
    var rangeFloor: Double {
        switch self {
        case .apparentC, .tempC, .wetBulbC, .dewC: return 2
        case .humidity:   return 0.1
        case .windKPH:    return 3
        case .uv:         return 3
        case .sun, .activity, .dress: return 1
        case .precipMM:   return 1
        case .precipProb: return 0.1
        case .cloud, .cloudHigh, .cloudLow, .cloudMed: return 0.2
        case .pressurePa: return 1000
        }
    }
}

/// Reads the raw observations (forecast/rating + the chosen scenario).
protocol PhysicalSource {
    func observation(_ v: PhysicalVar) -> Double
}

extension Feature {
    /// Minimum spread of this feature across the ratings before it may enter the
    /// model. A near-constant predictor is standardised by a tiny σ, which turns
    /// noise into a huge coefficient that explodes outside the observed range.
    /// Hinges inherit their parent's threshold (measured on the hinge itself).
    var minimumSpreadForInclusion: Double {
        switch self {
        case .apparentTempC, .hinge_cold_10, .hinge_warm_18, .hinge_hot_26: return 3
        case .apparentMinusTemp, .tempMinusWetBulb, .wetBulbMinusDewPoint:  return 1
        case .humidity:            return 0.1
        case .windSpeedKPH, .hinge_wind_15: return 5
        case .uvIndex, .hinge_uv_4: return 3
        case .sun, .activity, .dress, .isDaylight: return 1
        case .precipitationMM:     return 2
        case .precipProbability:   return 0.2
        case .cloudCover, .cloudCoverHigh, .cloudCoverLow, .cloudCoverMedium: return 0.2
        case .stationPressurePa:   return 1000
        // Interactions are judged through their parents (see `parentVars`):
        // both must individually have enough spread, which is unit-correct in a
        // way a single threshold on the product would not be.
        case .ix_apparent_humidity, .ix_apparent_uv, .ix_apparent_activity: return 0
        }
    }

    /// The observations this feature is built from. Used to decide which
    /// variables are already "covered" by the model (and so are range-checked
    /// against the in-model rule rather than the not-in-model one), and to gate
    /// interactions on their parents.
    var parentVars: [PhysicalVar] {
        switch self {
        case .apparentTempC, .hinge_cold_10, .hinge_warm_18, .hinge_hot_26: return [.apparentC]
        case .apparentMinusTemp:    return [.apparentC, .tempC]
        case .tempMinusWetBulb:     return [.tempC, .wetBulbC]
        case .wetBulbMinusDewPoint: return [.wetBulbC, .dewC]
        case .humidity:             return [.humidity]
        case .stationPressurePa:    return [.pressurePa]
        case .windSpeedKPH, .hinge_wind_15: return [.windKPH]
        case .precipProbability:    return [.precipProb]
        case .precipitationMM:      return [.precipMM]
        case .cloudCover:           return [.cloud]
        case .cloudCoverLow:        return [.cloudLow]
        case .cloudCoverMedium:     return [.cloudMed]
        case .cloudCoverHigh:       return [.cloudHigh]
        case .uvIndex, .hinge_uv_4: return [.uv]
        case .isDaylight:           return []
        case .activity:             return [.activity]
        case .dress:                return [.dress]
        case .sun:                  return [.sun]
        case .ix_apparent_humidity: return [.apparentC, .humidity]
        case .ix_apparent_uv:       return [.apparentC, .uv]
        case .ix_apparent_activity: return [.apparentC, .activity]
        }
    }
}

/// An observed lo…hi range, stored with the model so reliability can be judged
/// against the conditions the user actually rated in.
struct RangeBox: Codable, Equatable {
    var lo: Double
    var hi: Double
    var length: Double { max(0, hi - lo) }
    /// How far `v` sits outside the range (0 when inside).
    func distanceOutside(_ v: Double) -> Double {
        v < lo ? lo - v : (v > hi ? v - hi : 0)
    }
}

/// A "scenario" is the user's expected current state used at inference time
/// for self-report features that the forecast can't know.
struct Scenario {
    var activity: Int = 1
    var dress: Int = 0
    var sun: Int = 0
}

/// Forecast point + scenario combination acts as a feature source.
struct ForecastFeatureSource: FeatureSource, PhysicalSource {
    let p: ForecastPoint
    let scenario: Scenario

    func observation(_ v: PhysicalVar) -> Double {
        switch v {
        case .apparentC:  return p.apparentTemperatureC
        case .tempC:      return p.temperatureC
        case .wetBulbC:   return p.wetBulbC
        case .dewC:       return p.dewPointC
        case .humidity:   return p.humidity
        case .pressurePa: return p.stationPressurePa
        case .windKPH:    return p.windSpeedKPH
        case .uv:         return p.uvIndex
        case .precipProb: return p.precipProbability
        case .precipMM:   return p.precipitationMM
        case .cloud:      return p.cloudCover
        case .cloudLow:   return p.cloudCoverLow
        case .cloudMed:   return p.cloudCoverMedium
        case .cloudHigh:  return p.cloudCoverHigh
        case .activity:   return Double(scenario.activity)
        case .dress:      return Double(scenario.dress)
        case .sun:        return Double(scenario.sun)
        }
    }

    func value(for f: Feature) -> Double {
        switch f {
        case .apparentTempC:        return p.apparentTemperatureC
        case .apparentMinusTemp:    return p.apparentTemperatureC - p.temperatureC
        case .tempMinusWetBulb:     return p.temperatureC - p.wetBulbC
        case .wetBulbMinusDewPoint: return p.wetBulbC - p.dewPointC
        case .humidity:             return p.humidity
        case .stationPressurePa:    return p.stationPressurePa
        case .windSpeedKPH:         return p.windSpeedKPH
        case .precipProbability:    return p.precipProbability
        case .precipitationMM:      return p.precipitationMM
        case .cloudCover:           return p.cloudCover
        case .cloudCoverLow:        return p.cloudCoverLow
        case .cloudCoverMedium:     return p.cloudCoverMedium
        case .cloudCoverHigh:       return p.cloudCoverHigh
        case .uvIndex:              return p.uvIndex
        case .isDaylight:           return p.isDaylight ? 1 : 0
        case .activity:             return Double(scenario.activity)
        case .dress:                return Double(scenario.dress)
        case .sun:                  return Double(scenario.sun)
        // Hinges
        case .hinge_cold_10:        return max(0, 10 - p.apparentTemperatureC)
        case .hinge_warm_18:        return max(0, p.apparentTemperatureC - 18)
        case .hinge_hot_26:         return max(0, p.apparentTemperatureC - 26)
        case .hinge_wind_15:        return max(0, p.windSpeedKPH - 15)
        case .hinge_uv_4:           return max(0, p.uvIndex - 4)
        // Interactions
        case .ix_apparent_humidity: return p.apparentTemperatureC * p.humidity
        case .ix_apparent_uv:       return p.apparentTemperatureC * p.uvIndex
        case .ix_apparent_activity: return p.apparentTemperatureC * Double(scenario.activity)
        }
    }
}

// MARK: - Persistable regression state

struct RegressionState: Codable, Equatable {
    var selectedFeatures: [Feature]   // includes apparentTempC at index 0
    var coefficients: [Double]        // β0 (intercept) + one per selectedFeatures
    var means: [Double]               // means[i] for selectedFeatures[i]
    var stds: [Double]                // stds[i] for selectedFeatures[i] (≥ epsilon)
    var rSquared: Double
    var aicc: Double
    var ratingCount: Int
    var lastFitAt: Date

    /// Observed range of each *feature* in the model, and of each *observation*
    /// (whether or not it is in the model), plus the range of scores the user
    /// actually rated. These drive the range-based half of reliability: a
    /// forecast outside the conditions someone rated in is shown as a narrow
    /// band rather than a confident color. Optional so models saved before
    /// these existed still decode (they simply get leverage-only reliability).
    var featureRanges: [String: RangeBox]? = nil
    var observationRanges: [String: RangeBox]? = nil
    var scoreRange: RangeBox? = nil

    /// Inverse of the standardised normal-equations matrix (X'X)⁻¹ —
    /// the m × m matrix where m = selectedFeatures.count + 1 (intercept).
    /// Used to compute leverage / extrapolation diagnostics.
    /// Optional only so we can decode pre-leverage saved states;
    /// new fits always populate it.
    var invXtX: [[Double]]? = nil

    /// Predicted feels-like score (0…1000) for a feature source. May return
    /// values slightly outside [0, 1000]; callers clamp where needed.
    func predict(_ src: FeatureSource) -> Double {
        var y = coefficients[0]
        for (i, f) in selectedFeatures.enumerated() {
            let xStd = (src.value(for: f) - means[i]) / stds[i]
            y += coefficients[i + 1] * xStd
        }
        return y
    }

    /// Standardised augmented row [1, x₁_std, …, xₚ_std] for a query point.
    private func augmentedStdRow(_ src: FeatureSource) -> [Double] {
        let m = selectedFeatures.count + 1
        var x = [Double](repeating: 0, count: m)
        x[0] = 1.0
        for (j, f) in selectedFeatures.enumerated() {
            x[j + 1] = (src.value(for: f) - means[j]) / stds[j]
        }
        return x
    }

    /// Leverage (hat-matrix diagonal) for a query point.  Returns the
    /// scalar h = x' (X'X)⁻¹ x, where x is the standardised + intercept
    /// row for the query.
    ///
    ///   • At the centroid of training data h = 1/n (the floor).
    ///   • Average leverage over training points is m/n.
    ///   • Large h means the query lies far from training in a way that
    ///     respects the feature correlation structure (Mahalanobis-like).
    ///
    /// Returns nil if invXtX wasn't stored (legacy state); callers should
    /// then assume the model is in-range.
    func leverage(_ src: FeatureSource) -> Double? {
        guard let inv = invXtX else { return nil }
        let x = augmentedStdRow(src)
        let m = x.count
        var h = 0.0
        for i in 0..<m {
            var s = 0.0
            for j in 0..<m { s += inv[i][j] * x[j] }
            h += x[i] * s
        }
        return h
    }

    /// Opacity of the model prediction for `src`, based on leverage:
    ///   • h ≤ 2m/n → 1.0 (fully visible model)
    ///   • h ≥ 3m/n → 0.0 (invisible — model would be extrapolating)
    ///   • In between → linear fade.
    /// Used by the UI to fade the personalized color overlay where the
    /// forecast is outside the training distribution.
    func predictionOpacity(_ src: FeatureSource) -> Double {
        guard let h = leverage(src) else { return 1.0 }
        let mD = Double(selectedFeatures.count + 1)
        let nD = Double(ratingCount)
        guard nD > 0 else { return 1.0 }
        let lower = 2.0 * mD / nD
        let upper = 3.0 * mD / nD
        if h <= lower { return 1.0 }
        if h >= upper { return 0.0 }
        return 1.0 - (h - lower) / (upper - lower)
    }

    // MARK: Range-based reliability

    /// Narrowest width in 0…1, where 0.15 is "as narrow as it gets".
    static let minWidth = 0.15

    /// Linear ramp: full width at or below `free` range-lengths outside, minimum
    /// width at or beyond `full`.
    private func rampWidth(_ outside: Double, scale: Double, free: Double, full: Double) -> Double {
        guard scale > 0, full > free else { return outside > 0 ? Self.minWidth : 1 }
        let d = outside / scale
        if d <= free { return 1 }
        if d >= full { return Self.minWidth }
        return 1 - (1 - Self.minWidth) * (d - free) / (full - free)
    }

    /// Width from the *in-model* features: full inside the rated range, narrowest
    /// once a feature is a whole range-length outside it.
    func inModelRangeWidth(_ src: FeatureSource) -> Double {
        guard let ranges = featureRanges else { return 1 }
        var w = 1.0
        for f in selectedFeatures {
            guard let r = ranges[f.rawValue] else { continue }
            let outside = r.distanceOutside(src.value(for: f))
            guard outside > 0 else { continue }
            w = min(w, rampWidth(outside, scale: r.length, free: 0, full: 1))
        }
        return w
    }

    /// Width from the observations the model does *not* use. Without this, a
    /// model with no temperature term would predict just as confidently at 5 °C
    /// as at the 30 °C the user rated in — leverage cannot see a variable that
    /// isn't a feature.
    func notInModelRangeWidth(_ src: PhysicalSource) -> Double {
        guard let ranges = observationRanges else { return 1 }
        let covered = Set(selectedFeatures.flatMap { $0.parentVars })
        var w = 1.0
        for v in PhysicalVar.allCases where !covered.contains(v) {
            guard let r = ranges[v.rawValue] else { continue }
            let outside = r.distanceOutside(src.observation(v))
            guard outside > 0 else { continue }
            w = min(w, rampWidth(outside, scale: max(r.length, v.rangeFloor),
                                 free: 0.5, full: v.notInModelFactor))
        }
        return w
    }

    /// Width from the *predicted score* against the range of scores the user
    /// actually gave — a response-space check that catches a degenerate
    /// prediction no matter which feature caused it.
    func scoreRangeWidth(_ predicted: Double) -> Double {
        guard predicted.isFinite else { return Self.minWidth }
        guard let r = scoreRange else { return 1 }
        let outside = r.distanceOutside(predicted)
        guard outside > 0 else { return 1 }
        return rampWidth(outside, scale: r.length, free: 0.5, full: 1)
    }

    /// The width actually drawn: the narrowest of leverage, in-model range,
    /// not-in-model range and predicted-score range.
    func reliabilityWidth(features src: FeatureSource, physical: PhysicalSource,
                          predicted: Double) -> Double {
        min(min(predictionOpacity(src), inModelRangeWidth(src)),
            min(notInModelRangeWidth(physical), scoreRangeWidth(predicted)))
    }
}
