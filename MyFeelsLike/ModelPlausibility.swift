// SPDX-License-Identifier: GPL-3.0-or-later
//
//  ModelPlausibility.swift
//  MyFeelsLike
//
//  Guardrails that keep a personal model physically believable.
//
//  Why probing, not coefficient-reading: the features overlap (apparentTempC,
//  apparentMinusTemp, tempMinusWetBulb, the hinges and the interactions all move
//  with temperature), and the stored coefficients are per *standard deviation*,
//  not per °C. So the sign of any single coefficient says little on its own. We
//  instead ask the fitted model the question we actually care about:
//
//      "If it were 1 °C warmer, what would this model predict?"
//
//  by evaluating it at the user's typical conditions and again with every
//  temperature raised together, and taking the difference. That is a real
//  score-per-°C slope, comparable against a plausible physical range, and it
//  works no matter how many temperature-ish terms the model picked.
//
//  A second guardrail runs *before* fitting: a predictor the user never really
//  saw vary (e.g. cloud cover that stayed between 0.00 and 0.07) is excluded.
//  Standardisation divides by that tiny spread, so such a feature is pure noise
//  in-sample and explodes out-of-sample — a forecast at 80% cloud is then tens
//  of standard deviations away, which is how a model ends up predicting a score
//  far outside 0…1000.
//

import Foundation

// MARK: - A raw physical state we can perturb

/// The physical variables behind a rating/forecast, from which every `Feature`
/// can be recomputed. Lets us probe a fitted model with coherent what-ifs
/// (raise all temperatures by 1 °C, add 10 kph of wind, …).
struct PhysicalVector: FeatureSource {
    var tempC = 15.0, apparentC = 15.0, wetBulbC = 12.0, dewC = 8.0
    var humidity = 0.6, pressurePa = 101_325.0, windKPH = 5.0
    var precipProb = 0.0, precipMM = 0.0
    var cloud = 0.3, cloudLow = 0.2, cloudMed = 0.2, cloudHigh = 0.2, uv = 2.0
    var daylight = 1.0
    var activity = 1.0, dress = 0.0, sun = 0.0

    /// Must mirror `Rating.value(for:)` / `ForecastFeatureSource.value(for:)`.
    func value(for f: Feature) -> Double {
        switch f {
        case .apparentTempC:        return apparentC
        case .apparentMinusTemp:    return apparentC - tempC
        case .tempMinusWetBulb:     return tempC - wetBulbC
        case .wetBulbMinusDewPoint: return wetBulbC - dewC
        case .humidity:             return humidity
        case .stationPressurePa:    return pressurePa
        case .windSpeedKPH:         return windKPH
        case .precipProbability:    return precipProb
        case .precipitationMM:      return precipMM
        case .cloudCover:           return cloud
        case .cloudCoverLow:        return cloudLow
        case .cloudCoverMedium:     return cloudMed
        case .cloudCoverHigh:       return cloudHigh
        case .uvIndex:              return uv
        case .isDaylight:           return daylight
        case .activity:             return activity
        case .dress:                return dress
        case .sun:                  return sun
        case .hinge_cold_10:        return max(0, 10 - apparentC)
        case .hinge_warm_18:        return max(0, apparentC - 18)
        case .hinge_hot_26:         return max(0, apparentC - 26)
        case .hinge_wind_15:        return max(0, windKPH - 15)
        case .hinge_uv_4:           return max(0, uv - 4)
        case .ix_apparent_humidity: return apparentC * humidity
        case .ix_apparent_uv:       return apparentC * uv
        case .ix_apparent_activity: return apparentC * activity
        }
    }

    /// Every temperature raised together, so the *differences* between them
    /// (apparent−temp, temp−wet-bulb, wet-bulb−dew) stay put: this is "the same
    /// weather, but warmer", not "more humid".
    func warmed(by d: Double) -> PhysicalVector {
        var v = self
        v.tempC += d; v.apparentC += d; v.wetBulbC += d; v.dewC += d
        return v
    }
    func windier(by d: Double) -> PhysicalVector { var v = self; v.windKPH += d; return v }
    func moreActive(by d: Double) -> PhysicalVector { var v = self; v.activity += d; return v }
}

// MARK: - The checks

enum ModelPlausibility {

    // Score is 0…1000 across roughly the whole range of weather a person meets.
    // Even a very temperature-sensitive person should not swing the full scale
    // over a couple of degrees, and a model that barely responds to temperature
    // at all isn't a "feels like" model.
    /// Upper bound on |dScore/d°C| before we call a model implausible.
    static let maxScorePerDegreeC = 60.0
    /// Warmer must never read cooler. Zero is allowed: a model built only from
    /// self-report features (sun/activity/clothing) has no temperature response
    /// at all, which is legitimate for someone who has rated across a narrow
    /// temperature band — the not-in-model range check keeps it honest outside
    /// the conditions they rated in.
    static let minScorePerDegreeC = 0.0
    /// Tolerances for the weaker priors (allow small wrong-signed wobble).
    static let windTolerance = 25.0      // score units per +10 kph
    static let activityTolerance = 25.0  // score units per +1 activity step

    /// Observed spread (max − min) of a feature over the ratings.
    static func spread(_ f: Feature, in ratings: [Rating]) -> Double {
        let vs = ratings.map { $0.value(for: f) }
        guard let lo = vs.min(), let hi = vs.max() else { return 0 }
        return hi - lo
    }

    /// Observed range of a raw observation over the ratings.
    static func range(_ v: PhysicalVar, in ratings: [Rating]) -> RangeBox? {
        let vs = ratings.map { $0.observation(v) }
        guard let lo = vs.min(), let hi = vs.max() else { return nil }
        return RangeBox(lo: lo, hi: hi)
    }

    /// Candidates the data actually supports — drops near-constant predictors.
    /// Interactions are gated on their parents instead of on the product, whose
    /// units make a single threshold meaningless.
    static func eligible(_ features: [Feature], ratings: [Rating]) -> [Feature] {
        features.filter { f in
            switch f {
            case .ix_apparent_humidity, .ix_apparent_uv, .ix_apparent_activity:
                return f.parentVars.allSatisfy { parent in
                    guard let r = range(parent, in: ratings) else { return false }
                    return r.length >= parentSpreadRequirement(parent)
                }
            default:
                return spread(f, in: ratings) >= f.minimumSpreadForInclusion
            }
        }
    }

    /// The inclusion threshold expressed on a raw observation (for gating the
    /// interaction terms through their parents).
    private static func parentSpreadRequirement(_ v: PhysicalVar) -> Double {
        switch v {
        case .apparentC, .tempC, .wetBulbC, .dewC: return 3
        case .humidity: return 0.1
        case .windKPH:  return 5
        case .uv:       return 3
        case .activity, .dress, .sun: return 1
        case .precipMM: return 2
        case .precipProb: return 0.2
        case .cloud, .cloudHigh, .cloudLow, .cloudMed: return 0.2
        case .pressurePa: return 1000
        }
    }

    /// The user's typical conditions: the median of each physical variable, so
    /// the probe sits in the middle of the data rather than at an extreme.
    static func medianVector(_ ratings: [Rating]) -> PhysicalVector {
        func med(_ pick: (Rating) -> Double) -> Double {
            let v = ratings.map(pick).sorted()
            guard !v.isEmpty else { return 0 }
            return v.count % 2 == 1 ? v[v.count / 2]
                                    : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
        }
        return PhysicalVector(
            tempC: med { $0.temperatureC }, apparentC: med { $0.apparentTemperatureC },
            wetBulbC: med { $0.wetBulbC }, dewC: med { $0.dewPointC },
            humidity: med { $0.humidity }, pressurePa: med { $0.stationPressurePa },
            windKPH: med { $0.windSpeedKPH }, precipProb: med { $0.precipProbability },
            precipMM: med { $0.precipitationMM }, cloud: med { $0.cloudCover },
            cloudLow: med { $0.cloudCoverLow }, cloudMed: med { $0.cloudCoverMedium },
            cloudHigh: med { $0.cloudCoverHigh }, uv: med { $0.uvIndex },
            daylight: med { $0.isDaylight ? 1 : 0 },
            activity: med { Double($0.activity) }, dress: med { Double($0.dress) },
            sun: med { Double($0.sun) })
    }

    /// Why a model was rejected (logged; also surfaced to the user in plain words).
    enum Rejection: Equatable {
        case coolerWhenWarmer(perDegreeC: Double)
        case temperatureResponseTooSteep(perDegreeC: Double)
        case warmerWhenWindier(per10KPH: Double)
        case coolerWhenMoreActive(perStep: Double)
        case nonFiniteCoefficients

        var reason: String {
            switch self {
            case .coolerWhenWarmer(let d):
                return String(format: "predicts %.0f points cooler per +1 °C", -d)
            case .temperatureResponseTooSteep(let d):
                return String(format: "predicts %.0f points per +1 °C, which is implausibly steep", d)
            case .warmerWhenWindier(let d):
                return String(format: "predicts %.0f points warmer per +10 kph of wind", d)
            case .coolerWhenMoreActive(let d):
                return String(format: "predicts %.0f points cooler per activity step", -d)
            case .nonFiniteCoefficients:
                return "has non-finite coefficients"
            }
        }
    }

    /// Probe a fitted model with coherent what-ifs. Returns nil when it behaves
    /// plausibly, else the first violated prior.
    static func check(_ state: RegressionState, ratings: [Rating]) -> Rejection? {
        guard state.coefficients.allSatisfy({ $0.isFinite }),
              state.means.allSatisfy({ $0.isFinite }),
              state.stds.allSatisfy({ $0.isFinite && $0 > 0 }) else { return .nonFiniteCoefficients }

        let base = medianVector(ratings)
        let y0 = state.predict(base)
        guard y0.isFinite else { return .nonFiniteCoefficients }

        // Temperature: the one prior we insist on. Averaged over a few degrees
        // so a hinge sitting exactly at the probe point can't dominate. A model
        // with no temperature term scores exactly 0 here, which is allowed.
        let perDegree = (state.predict(base.warmed(by: 3)) - state.predict(base.warmed(by: -3))) / 6
        guard perDegree.isFinite else { return .nonFiniteCoefficients }
        if perDegree < minScorePerDegreeC { return .coolerWhenWarmer(perDegreeC: perDegree) }
        if perDegree > maxScorePerDegreeC { return .temperatureResponseTooSteep(perDegreeC: perDegree) }

        // Wind should not make it read warmer (only checked when wind is in play).
        if state.selectedFeatures.contains(where: { $0 == .windSpeedKPH || $0 == .hinge_wind_15 }) {
            let per10 = state.predict(base.windier(by: 10)) - y0
            if per10 > windTolerance { return .warmerWhenWindier(per10KPH: per10) }
        }

        // More activity should not make it read cooler.
        if state.selectedFeatures.contains(where: { $0 == .activity || $0 == .ix_apparent_activity }) {
            let perStep = state.predict(base.moreActive(by: 1)) - y0
            if perStep < -activityTolerance { return .coolerWhenMoreActive(perStep: perStep) }
        }
        return nil
    }
}
