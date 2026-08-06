// SPDX-License-Identifier: GPL-3.0-or-later
//
//  ScoreScaleMigrationTests.swift
//  MyFeelsLikeTests
//
//  Converting ratings from the previous color scale to the redesigned one. The
//  promise is that a rating keeps the color the user picked (below pure red,
//  where both scales share their anchors), so the tests check colors, not just
//  numbers.
//

import Testing
import Foundation
import SwiftUI
@testable import MyFeelsLike

struct ScoreScaleMigrationTests {

    private func rgb(_ c: Color) -> (Double, Double, Double) {
        let ui = UIColor(c)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    private func distance(_ a: Color, _ b: Color) -> Double {
        let (r1, g1, b1) = rgb(a), (r2, g2, b2) = rgb(b)
        return ((r1 - r2) * (r1 - r2) + (g1 - g2) * (g1 - g2) + (b1 - b2) * (b1 - b2)).squareRoot()
    }

    /// The endpoints are fixed points: white stays white, the hottest end stays
    /// the hottest end.
    @Test func endpointsAreUnchanged() {
        #expect(abs(ScoreScaleMigration.convert(0) - 0) < 1e-9)
        #expect(abs(ScoreScaleMigration.convert(1000) - 1000) < 1e-9)
    }

    /// Pure red is the anchor the two scales share; it must land exactly on the
    /// new red, from either direction.
    @Test func pureRedMapsToNewRed() {
        let converted = ScoreScaleMigration.convert(ScoreScaleMigration.legacyRed)
        #expect(abs(converted - ScoreScaleMigration.newRed) < 1e-6)
    }

    /// Below red, the whole point: the color the user picked is preserved.
    @Test func colorsArePreservedBelowRed() {
        var worst = 0.0
        for old in stride(from: 0.0, through: ScoreScaleMigration.legacyRed, by: 5) {
            let d = distance(ColorScale.legacyColor(forScore: old),
                             ColorScale.color(forScore: ScoreScaleMigration.convert(old)))
            worst = max(worst, d)
        }
        // The only mismatch is that the old green was pure (0,1,0) while the new
        // one is (0,0.85,0), so the greenest ratings land on the nearest green.
        // That caps the error at 0.15 in one channel.
        #expect(worst < 0.16, "worst color distance \(worst)")
    }

    /// Conversion must never reorder ratings: hotter stays hotter.
    @Test func conversionIsMonotonic() {
        var previous = -1.0
        for old in stride(from: 0.0, through: 1000.0, by: 1) {
            let v = ScoreScaleMigration.convert(old)
            #expect(v >= previous - 1e-9, "not monotonic at \(old)")
            previous = v
        }
    }

    /// Above red the old scale ran through purple to black with no equivalent,
    /// so it is a straight line onto red…dark-red — continuous at red.
    @Test func aboveRedIsLinearAndContinuous() {
        let r1 = ScoreScaleMigration.legacyRed, r2 = ScoreScaleMigration.newRed
        let mid = (r1 + 1000) / 2
        let expected = 1000 - (1000 - mid) / (1000 - r1) * (1000 - r2)
        #expect(abs(ScoreScaleMigration.convert(mid) - expected) < 1e-6)
        // Continuity: just below red and just above agree.
        #expect(abs(ScoreScaleMigration.convert(r1 - 0.001)
                    - ScoreScaleMigration.convert(r1 + 0.001)) < 0.01)
    }

    /// Everything above red is squeezed into the top 12% of the new scale, so a
    /// mid-purple rating still reads as clearly hot.
    @Test func oldPurpleStaysHot() {
        let purple = ScoreScaleMigration.legacyAnchorScores[5]
        let converted = ScoreScaleMigration.convert(purple)
        #expect(converted > ScoreScaleMigration.newRed)
        #expect(converted < 1000)
    }

    /// migrate() keeps the original in score1, converts in place, and is safe to
    /// run twice — a second pass must not convert an already-converted rating.
    @Test func migrateIsIdempotentAndKeepsTheOriginal() {
        let ratings = [200.0, 480.0, 800.0].map {
            Rating(feelsLikeScore: $0, activity: 1, dress: 0, sun: 0,
                   snapshot: mkForecastPoint(apparentC: 20))
        }
        let originals = ratings.map(\.feelsLikeScore)

        let first = ScoreScaleMigration.migrate(ratings)
        #expect(first == 3)
        for (r, original) in zip(ratings, originals) {
            #expect(r.feelsLikeScore1 == original)
            #expect(abs(r.feelsLikeScore - ScoreScaleMigration.convert(original)) < 1e-9)
        }

        let converted = ratings.map(\.feelsLikeScore)
        #expect(ScoreScaleMigration.migrate(ratings) == 0)
        #expect(ratings.map(\.feelsLikeScore) == converted)
    }
}
