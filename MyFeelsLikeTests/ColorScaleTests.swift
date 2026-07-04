//
//  ColorScaleTests.swift
//  MyFeelsLikeTests
//

import Testing
import SwiftUI
import UIKit
@testable import MyFeelsLike

struct ColorScaleTests {

    private func rgb(_ c: Color) -> (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    @Test func endpointsAreWhiteAndBlack() {
        let (r0, g0, b0) = rgb(ColorScale.color(forScore: ColorScale.minScore))
        #expect(r0 > 0.95 && g0 > 0.95 && b0 > 0.95)   // coldest = white
        let (r1, g1, b1) = rgb(ColorScale.color(forScore: ColorScale.maxScore))
        #expect(r1 < 0.05 && g1 < 0.05 && b1 < 0.05)   // hottest = black
    }

    @Test func scoreClampsOutsideRange() {
        #expect(rgb(ColorScale.color(forScore: -500)) == rgb(ColorScale.color(forScore: 0)))
        #expect(rgb(ColorScale.color(forScore: 5000)) == rgb(ColorScale.color(forScore: 1000)))
    }

    @Test func contrastingTextFlipsWithBackground() {
        // White background → dark text; black background → light text.
        #expect(rgb(ColorScale.contrastingText(forScore: 0)).0 < 0.5)
        #expect(rgb(ColorScale.contrastingText(forScore: 1000)).0 > 0.5)
    }

    // MARK: - Forecast colour must match the colour shown while rating
    //
    // Regression for the bug where the forecast painted cooler colours than
    // the user picked: the rating column spaced its gradient anchors on a
    // power curve while the display used linear spacing. `color(forScore:)`
    // must now reproduce, for any score, the exact colour under the rating
    // indicator at the scroll position that records that score.

    /// Sample a SwiftUI gradient at an absolute location in [0, 1].
    private func sample(_ gradient: Gradient, at loc: Double) -> (Double, Double, Double) {
        let stops = gradient.stops
        for i in 0..<(stops.count - 1) {
            let a = stops[i], b = stops[i + 1]
            guard Double(b.location) > Double(a.location) else { continue }
            if Double(a.location) <= loc && loc <= Double(b.location) {
                let t = (loc - Double(a.location)) / (Double(b.location) - Double(a.location))
                let (r1, g1, b1) = rgb(a.color)
                let (r2, g2, b2) = rgb(b.color)
                return (r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t)
            }
        }
        return rgb(stops.last!.color)
    }

    @Test func forecastColourMatchesRatingColumnColour() {
        // The rating column reads its score from the indicator at the vertical
        // centre of the viewport; a score s sits at absolute gradient location
        // (1.25 - s/1000) / 1.5 (derived from the column's 3×-viewport height
        // and hot-at-top orientation).
        let gradient = ColorScoreColumn.paddedScoreGradient()
        for s in stride(from: 0.0, through: 1000.0, by: 50.0) {
            let loc = (1.25 - s / 1000.0) / 1.5
            let (rr, gg, bb) = sample(gradient, at: loc)
            let (cr, cg, cb) = rgb(ColorScale.color(forScore: s))
            #expect(abs(rr - cr) < 0.02, "R mismatch at score \(s)")
            #expect(abs(gg - cg) < 0.02, "G mismatch at score \(s)")
            #expect(abs(bb - cb) < 0.02, "B mismatch at score \(s)")
        }
    }

    /// Guards the direction of the fix: a mid-scale score must render warmer
    /// (more red, less blue) than a low score — i.e. the old cool-shift is gone.
    @Test func higherScoresRenderWarmerThanLowerScores() {
        let (rHi, _, bHi) = rgb(ColorScale.color(forScore: 500))
        let (rLo, _, bLo) = rgb(ColorScale.color(forScore: 200))
        #expect(rHi > rLo)   // warmer = more red
        #expect(bHi < bLo)   // warmer = less blue
    }
}
