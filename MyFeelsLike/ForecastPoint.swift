//
//  ForecastPoint.swift
//  MyFeelsLike
//
//  One hour of weather (or the "now" nowcast) plus the personalised
//  "feels like" prediction. Pure value type with no UI or platform
//  dependencies so it can be shared between the iOS app and the watch app.
//

import Foundation

struct ForecastPoint: Identifiable, Codable {
    /// Where this point sits relative to "now":
    ///   .historic — observed/analysed past hour (full field set)
    ///   .current  — Apple's nowcast; lacks precip & cloud-by-altitude
    ///   .forecast — future hourly forecast (full field set)
    enum Kind: Codable { case historic, current, forecast }

    var id = UUID()
    var kind: Kind = .forecast
    let date: Date
    let symbolName: String
    let isDaylight: Bool
    let uvIndex: Double
    let temperatureF: Double
    let temperatureC: Double
    let apparentTemperatureF: Double
    let apparentTemperatureC: Double
    let wetBulbF: Double
    let wetBulbC: Double
    let dewPointF: Double
    let dewPointC: Double
    let precipProbability: Double   // 0…1
    let precipitationMM: Double
    let windSpeedMPH: Double
    let windSpeedKPH: Double
    let windGustMPH: Double
    let windGustKPH: Double
    let cloudCover: Double          // 0…1
    let cloudCoverLow: Double       // 0…1
    let cloudCoverMedium: Double    // 0…1
    let cloudCoverHigh: Double      // 0…1
    let humidity: Double            // 0…1
    let stationPressurePa: Double
    /// Personalised "feels like" score (0…1000) — populated by the regression
    /// once enough user ratings exist. Nil = no model yet.
    var myFeelsLikeScore: Double?
    /// Visual opacity of the personalised colour at this point:
    ///   1.0 = forecast firmly within training distribution
    ///   0.0 = extrapolation (don't trust the model here)
    /// Used by the chart background and the table cell to fade the colour
    /// where the model becomes unreliable.
    var myFeelsLikeOpacity: Double = 0.0

    /// Sun/shade split of the personalised score (for the 24h colour band): the
    /// same prediction evaluated with sun forced to full-sun (+1) and to shade
    /// (−1), holding the rest of the scenario fixed. Populated only where the
    /// band needs it (the 24h series); nil when there's no model.
    var myFeelsLikeSunScore: Double?
    var myFeelsLikeSunOpacity: Double = 0.0
    var myFeelsLikeShadeScore: Double?
    var myFeelsLikeShadeOpacity: Double = 0.0

    mutating func applyPrediction(state: RegressionState?, scenario: Scenario) {
        guard let state else {
            myFeelsLikeScore = nil
            myFeelsLikeOpacity = 0
            return
        }
        let src = ForecastFeatureSource(p: self, scenario: scenario)
        myFeelsLikeScore   = state.predict(src)
        myFeelsLikeOpacity = state.predictionOpacity(src)
    }

    /// Compute the in-sun and in-shade variants of the score, for the split
    /// 24h colour band. Only worth showing when the model actually learned a
    /// sun effect (`.sun` ∈ selectedFeatures); otherwise both come out equal.
    mutating func applySunShadePrediction(state: RegressionState?, scenario: Scenario) {
        guard let state else {
            myFeelsLikeSunScore = nil;   myFeelsLikeSunOpacity = 0
            myFeelsLikeShadeScore = nil; myFeelsLikeShadeOpacity = 0
            return
        }
        var sunScenario = scenario;   sunScenario.sun = 1
        var shadeScenario = scenario; shadeScenario.sun = -1
        let sunSrc = ForecastFeatureSource(p: self, scenario: sunScenario)
        let shadeSrc = ForecastFeatureSource(p: self, scenario: shadeScenario)
        myFeelsLikeSunScore     = state.predict(sunSrc)
        myFeelsLikeSunOpacity   = state.predictionOpacity(sunSrc)
        myFeelsLikeShadeScore   = state.predict(shadeSrc)
        myFeelsLikeShadeOpacity = state.predictionOpacity(shadeSrc)
    }
}
