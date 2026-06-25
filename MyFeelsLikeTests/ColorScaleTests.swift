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
}
