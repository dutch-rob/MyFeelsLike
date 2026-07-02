//
//  TestSupport.swift
//  MyFeelsLikeTests
//
//  Shared helpers for the unit tests: an in-memory FeatureSource and small
//  builders for ForecastPoint / Rating so tests don't touch SwiftData,
//  WeatherKit or the network.
//

import Foundation
@testable import MyFeelsLike

/// In-memory feature source: returns the value you set, or 0.
struct StubFeatures: FeatureSource {
    var values: [Feature: Double] = [:]
    func value(for f: Feature) -> Double { values[f] ?? 0 }
}

/// Build a ForecastPoint with only the fields a test cares about; everything
/// else defaults to a harmless zero.
func mkForecastPoint(
    date: Date = Date(),
    tempC: Double = 0, apparentC: Double = 0, wetBulbC: Double = 0, dewC: Double = 0,
    humidity: Double = 0.5, windKPH: Double = 0, uv: Double = 0,
    cloud: Double = 0, stationPa: Double = 100_000, isDaylight: Bool = true,
    score: Double? = nil
) -> ForecastPoint {
    ForecastPoint(
        date: date, symbolName: "sun.max", isDaylight: isDaylight, uvIndex: uv,
        temperatureF: tempC * 9/5 + 32, temperatureC: tempC,
        apparentTemperatureF: apparentC * 9/5 + 32, apparentTemperatureC: apparentC,
        wetBulbF: wetBulbC * 9/5 + 32, wetBulbC: wetBulbC,
        dewPointF: dewC * 9/5 + 32, dewPointC: dewC,
        precipProbability: 0, precipitationMM: 0,
        windSpeedMPH: windKPH / 1.60934, windSpeedKPH: windKPH,
        windGustMPH: 0, windGustKPH: 0,
        cloudCover: cloud, cloudCoverLow: 0, cloudCoverMedium: 0, cloudCoverHigh: 0,
        humidity: humidity, stationPressurePa: stationPa,
        myFeelsLikeScore: score)
}

/// Build a synthetic Rating. `feelsLike` is the 0…1000 target score.
func mkRating(apparent: Double, humidity: Double = 0.5, wind: Double = 0,
              activity: Int = 1, dress: Int = 0, sun: Int = 0,
              feelsLike: Double) -> Rating {
    Rating(feelsLikeScore: feelsLike, activity: activity, dress: dress, sun: sun,
           snapshot: mkForecastPoint(apparentC: apparent, humidity: humidity, windKPH: wind))
}
