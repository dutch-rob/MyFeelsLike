// SPDX-License-Identifier: GPL-3.0-or-later
//
//  ExportImportTests.swift
//  MyFeelsLikeTests
//
//  Round-trip coverage for the Settings "Export ratings as JSON…" / "Import
//  ratings from JSON…" feature. RatingExport/ModelExport/FullExport each
//  duplicate Rating's field list by hand; if one of them drifts (a field
//  added to Rating but missed in an export/import type) a restored backup
//  would silently lose or zero out data — no crash, nothing visibly wrong,
//  exactly the class of bug already hit once on this screen (see
//  ColorScoreColumnTests).
//

import Testing
import Foundation
@testable import MyFeelsLike

struct ExportImportTests {

    /// Every relevant field gets a distinct, recognizable value so a bug
    /// that swaps or drops a field is caught by exact comparison rather
    /// than hidden behind coincidentally-matching defaults.
    private func mkDistinctForecastPoint() -> ForecastPoint {
        ForecastPoint(
            kind: .forecast,
            date: Date(timeIntervalSince1970: 2_000_000_000),
            symbolName: "sun.max",
            isDaylight: true,
            uvIndex: 3,
            temperatureF: 68, temperatureC: 20,
            apparentTemperatureF: 71.6, apparentTemperatureC: 22,
            wetBulbF: 60.8, wetBulbC: 16,
            dewPointF: 50, dewPointC: 10,
            precipProbability: 0.35, precipitationMM: 1.2,
            windSpeedMPH: 6.2, windSpeedKPH: 10,
            windGustMPH: 9.3, windGustKPH: 15,
            cloudCover: 0.4, cloudCoverLow: 0.1, cloudCoverMedium: 0.2, cloudCoverHigh: 0.3,
            humidity: 0.55, stationPressurePa: 99_500
        )
    }

    private func mkDistinctRating(placeID: UUID? = UUID()) -> Rating {
        Rating(
            timestamp: Date(timeIntervalSince1970: 2_000_000_000),
            placeID: placeID,
            feelsLikeScore: 733, activity: 2, dress: -1, sun: 1,
            snapshot: mkDistinctForecastPoint()
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    // MARK: - RatingExport <-> Rating

    @Test func ratingExportRoundTripsAllFieldsThroughJSON() throws {
        let original = mkDistinctRating()
        let exported = RatingExport(from: original, state: nil)
        let data = try encode(exported)
        let decoded = try decode(RatingExport.self, from: data)
        let restored = decoded.makeRating()

        #expect(restored.id == original.id)
        #expect(restored.timestamp == original.timestamp)
        #expect(restored.placeID == original.placeID)
        #expect(restored.feelsLikeScore == original.feelsLikeScore)
        #expect(restored.activity == original.activity)
        #expect(restored.dress == original.dress)
        #expect(restored.sun == original.sun)
        #expect(restored.temperatureC == original.temperatureC)
        #expect(restored.apparentTemperatureC == original.apparentTemperatureC)
        #expect(restored.wetBulbC == original.wetBulbC)
        #expect(restored.dewPointC == original.dewPointC)
        #expect(restored.humidity == original.humidity)
        #expect(restored.stationPressurePa == original.stationPressurePa)
        #expect(restored.windSpeedKPH == original.windSpeedKPH)
        #expect(restored.precipProbability == original.precipProbability)
        #expect(restored.precipitationMM == original.precipitationMM)
        #expect(restored.cloudCover == original.cloudCover)
        #expect(restored.cloudCoverLow == original.cloudCoverLow)
        #expect(restored.cloudCoverMedium == original.cloudCoverMedium)
        #expect(restored.cloudCoverHigh == original.cloudCoverHigh)
        #expect(restored.uvIndex == original.uvIndex)
        #expect(restored.isDaylight == original.isDaylight)
    }

    @Test func ratingExportRoundTripsNilPlaceID() throws {
        // "Current location" ratings carry no placeID — make sure nil
        // survives rather than being coerced to some sentinel UUID.
        let original = mkDistinctRating(placeID: nil)
        let data = try encode(RatingExport(from: original, state: nil))
        let restored = try decode(RatingExport.self, from: data).makeRating()
        #expect(restored.placeID == nil)
    }

    @Test func ratingExportDiagnosticsAreNilWithoutAModel() {
        let exported = RatingExport(from: mkDistinctRating(), state: nil)
        #expect(exported.modelPredictionScore == nil)
        #expect(exported.leverage_h == nil)
        #expect(exported.predictionOpacity == nil)
    }

    @Test func ratingExportDiagnosticsMatchModelWhenProvided() {
        // n = 8 → budget 0, so this fits intercept + apparentTempC only
        // (same shape as FeelsLikeRegressionTests.recoversSlopeOfApparentTempOnly).
        let apparents = [10.0, 12, 15, 18, 22, 25, 28, 30]
        let ratings = apparents.map { a in mkRating(apparent: a, feelsLike: 8 * a + 100) }
        let state = FeelsLikeRegression.fit(ratings: ratings)!

        let target = ratings[0]
        let exported = RatingExport(from: target, state: state)
        #expect(exported.modelPredictionScore == state.predict(target))
        #expect(exported.leverage_h == state.leverage(target))
        #expect(exported.predictionOpacity == state.predictionOpacity(target))
        #expect(exported.leverage_h != nil)   // sanity: this rating was in the training set
    }

    // MARK: - FullExport <-> [Rating]

    @Test func fullExportRoundTripsMultipleRatingsAndModel() throws {
        let apparents = [10.0, 12, 15, 18, 22, 25, 28, 30]
        let ratings = apparents.map { a in mkRating(apparent: a, feelsLike: 8 * a + 100) }
        let state = FeelsLikeRegression.fit(ratings: ratings)!

        let full = FullExport(
            exportedAt: Date(timeIntervalSince1970: 2_000_000_000),
            model: ModelExport(from: state, ratings: ratings),
            ratings: ratings.map { RatingExport(from: $0, state: state) }
        )
        let data = try encode(full)
        let decoded = try decode(FullExport.self, from: data)

        #expect(decoded.ratings.count == ratings.count)
        let restored = decoded.ratings.map { $0.makeRating() }
        #expect(Set(restored.map(\.id)) == Set(ratings.map(\.id)))
        for (r, original) in zip(restored, ratings) {
            #expect(r.feelsLikeScore == original.feelsLikeScore)
        }

        #expect(decoded.model?.ratingCount == state.ratingCount)
        #expect(decoded.model?.features == state.selectedFeatures.map { $0.rawValue })
    }

    @Test func fullExportOmitsModelWhenNoneWasFit() throws {
        let full = FullExport(exportedAt: Date(timeIntervalSince1970: 2_000_000_000),
                              model: nil, ratings: [])
        let data = try encode(full)
        let decoded = try decode(FullExport.self, from: data)
        #expect(decoded.model == nil)
        #expect(decoded.ratings.isEmpty)
    }

    // MARK: - ModelExport de-standardisation math

    @Test func modelExportDestandardizesInterceptAndCoefficients() {
        // Hand-built state: single feature, β0=500 (standardised intercept),
        // β1=100 (standardised slope), mean=20, std=5.
        // raw_coef(feature) = β1 / std = 100 / 5 = 20.
        // raw_coef(intercept) = β0 - β1 * mean / std = 500 - 100*20/5 = 100.
        let state = RegressionState(
            selectedFeatures: [.apparentTempC],
            coefficients: [500, 100],
            means: [20], stds: [5],
            rSquared: 0.9, aicc: 10, ratingCount: 3,
            lastFitAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
        let dummyRatings = (0..<3).map { _ in mkRating(apparent: 20, feelsLike: 500) }
        let model = ModelExport(from: state, ratings: dummyRatings)

        #expect(model.intercept.std_coef == 500)
        #expect(model.intercept.raw_coef == 100)
        #expect(model.coefficients.count == 1)
        #expect(model.coefficients[0].feature == Feature.apparentTempC.rawValue)
        #expect(model.coefficients[0].std_coef == 100)
        #expect(model.coefficients[0].raw_coef == 20)
    }

    @Test func modelExportLeverageBucketsAccountForEveryTrainingRating() {
        let apparents = [10.0, 12, 15, 18, 22, 25, 28, 30]
        let ratings = apparents.map { a in mkRating(apparent: a, feelsLike: 8 * a + 100) }
        let state = FeelsLikeRegression.fit(ratings: ratings)!
        let model = ModelExport(from: state, ratings: ratings)

        #expect(model.diagnostics.m == state.selectedFeatures.count + 1)
        // Every training rating must land in exactly one leverage bucket —
        // if the boundary logic double-counted or skipped one, this would
        // drift without ever crashing or looking wrong in the exported file.
        let bucketed = model.diagnostics.n_inRange
                     + model.diagnostics.n_blended
                     + model.diagnostics.n_extrapolated
        #expect(bucketed == ratings.count)
    }

    // MARK: - decodeRatingsForImport (decode + dedup, no SwiftData needed)

    @Test func importDecodesCurrentFullExportEnvelope() throws {
        let ratings = [mkDistinctRating(), mkDistinctRating()]
        let full = FullExport(exportedAt: Date(timeIntervalSince1970: 2_000_000_000),
                              model: nil,
                              ratings: ratings.map { RatingExport(from: $0, state: nil) })
        let data = try encode(full)

        let result = try decodeRatingsForImport(data: data, existingIDs: [])
        #expect(result.toInsert.count == 2)
        #expect(result.skippedCount == 0)
        #expect(Set(result.toInsert.map(\.id)) == Set(ratings.map(\.id)))
    }

    /// Some older exports were a bare `[RatingExport]` array with no
    /// `FullExport` envelope. `decodeRatingsForImport` tries the envelope
    /// first via `try?` and silently falls back — if that fallback ever
    /// broke, old backups would stop importing with no obvious cause.
    @Test func importDecodesLegacyFlatArrayFormat() throws {
        let ratings = [mkDistinctRating(), mkDistinctRating()]
        let exports = ratings.map { RatingExport(from: $0, state: nil) }
        let data = try encode(exports)   // no FullExport wrapper

        let result = try decodeRatingsForImport(data: data, existingIDs: [])
        #expect(result.toInsert.count == 2)
        #expect(Set(result.toInsert.map(\.id)) == Set(ratings.map(\.id)))
    }

    @Test func importSkipsRatingsAlreadyPresentByID() throws {
        let keep = mkDistinctRating()
        let alreadyPresent = mkDistinctRating()
        let full = FullExport(
            exportedAt: Date(timeIntervalSince1970: 2_000_000_000),
            model: nil,
            ratings: [keep, alreadyPresent].map { RatingExport(from: $0, state: nil) }
        )
        let data = try encode(full)

        let result = try decodeRatingsForImport(data: data, existingIDs: [alreadyPresent.id])
        #expect(result.toInsert.count == 1)
        #expect(result.toInsert[0].id == keep.id)
        #expect(result.skippedCount == 1)
    }

    @Test func importThrowsRatherThanSilentlySucceedingOnGarbageData() {
        let garbage = Data("not json".utf8)
        #expect(throws: (any Error).self) {
            try decodeRatingsForImport(data: garbage, existingIDs: [])
        }
    }
}
