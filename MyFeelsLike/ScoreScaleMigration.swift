// SPDX-License-Identifier: GPL-3.0-or-later
//
//  ScoreScaleMigration.swift
//  MyFeelsLike
//
//  Converts ratings given on the previous color scale to the redesigned one, so
//  beta testers keep the ratings they have already given instead of starting
//  over (or, worse, carrying on with two scales mixed in one model).
//
//  The two scales run through the same sequence of anchor colors up to pure red
//  — white, blue, green, yellow, red — just at different positions:
//
//        anchor    old score    new score
//        white          0            0
//        blue         103.6        250
//        green        216.0        500
//        yellow       340.2        690
//        red          482.7        880
//
//  So below red a rating keeps exactly the color the user actually picked: we
//  find which segment the old score sits in, and place it at the same fraction
//  of the matching new segment. Both scales use the same anchor colors there,
//  pure green included, so the RGB comes out identical.
//
//  Above red the old scale continues through purple to black while the new one
//  only darkens red, so there is no color to match and the rest is mapped
//  linearly onto red…dark-red:
//
//        score = 1000 − (1000 − score1) / (1000 − R1) × (1000 − R2)
//
//  which is continuous at red and maps black to the hottest end.
//

import Foundation

enum ScoreScaleMigration {

    /// Old-scale positions of the anchors, cold → hot. Derived from the legacy
    /// power warp rather than typed in, so they cannot drift from the legacy
    /// color function that `ColorScale.legacyColor` still implements.
    static let legacyAnchorScores: [Double] = {
        let m = Double(ColorScale.anchors.count - 1)          // 6 segments
        return (0...Int(m)).map { i in
            // Legacy anchor i (cold → hot) sat at reversed index m − i.
            ColorScale.maxScore * (1 - pow((m - Double(i)) / m, ColorScale.scoreGradientExponent))
        }
    }()

    /// New-scale positions of the same anchors, cold → hot, up to red.
    static var newAnchorScores: [Double] { ColorScale.scoreAnchors.map(\.score) }

    /// Old score of pure red (R1) — the last anchor the two scales share.
    static var legacyRed: Double { legacyAnchorScores[4] }
    /// New score of pure red (R2).
    static var newRed: Double { newAnchorScores[4] }

    /// Convert one score from the previous scale to the current one.
    static func convert(_ score1: Double) -> Double {
        guard score1.isFinite else { return 500 }
        let s = min(max(score1, ColorScale.minScore), ColorScale.maxScore)

        // At or above pure red: no matching color exists on the new scale
        // (old purple/black have no equivalent), so map linearly onto red…hot.
        if s >= legacyRed {
            return ColorScale.maxScore
                - (ColorScale.maxScore - s) / (ColorScale.maxScore - legacyRed)
                * (ColorScale.maxScore - newRed)
        }

        // Below red: keep the exact color by matching anchor segments.
        for i in 0..<4 where s < legacyAnchorScores[i + 1] {
            let lo = legacyAnchorScores[i], hi = legacyAnchorScores[i + 1]
            let t = hi > lo ? (s - lo) / (hi - lo) : 0
            let nLo = newAnchorScores[i], nHi = newAnchorScores[i + 1]
            return nLo + (nHi - nLo) * t
        }
        return newRed
    }

    /// One-shot conversion of every stored rating. Returns how many were
    /// changed. A rating that already carries `feelsLikeScore1` has been
    /// converted before and is left alone, so this is safe to run twice.
    @discardableResult
    static func migrate(_ ratings: [Rating]) -> Int {
        var changed = 0
        for r in ratings where r.feelsLikeScore1 == nil {
            r.feelsLikeScore1 = r.feelsLikeScore
            r.feelsLikeScore = convert(r.feelsLikeScore)
            changed += 1
        }
        return changed
    }
}
