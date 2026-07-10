//
//  ColorScoreColumnTests.swift
//  MyFeelsLikeTests
//
//  Regression coverage for the Rate Feels Like color column: the scroll
//  offset → score mapping, and the gradient it paints. A prior bug here
//  (fixed in "Fix rating screen always recording 1000…") had the offset
//  read stuck at the top of the column, so every rating silently saved
//  1000 no matter where the user scrolled to — nothing about the UI looked
//  wrong at a glance, only the saved value was.
//

import Testing
import SwiftUI
import UIKit
@testable import MyFeelsLike

struct ColorScoreColumnTests {

    private func rgb(_ c: Color) -> (Double, Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    // MARK: - score(forOffsetY:usableRange:)

    @Test func topOfScrollIsHottest() {
        #expect(ColorScoreColumn.score(forOffsetY: 0, usableRange: 200) == 1000)
    }

    @Test func bottomOfScrollIsColdest() {
        #expect(ColorScoreColumn.score(forOffsetY: 200, usableRange: 200) == 0)
    }

    @Test func midScrollIsMidScore() {
        #expect(ColorScoreColumn.score(forOffsetY: 100, usableRange: 200) == 500)
    }

    @Test func offsetBeyondRangeClamps() {
        #expect(ColorScoreColumn.score(forOffsetY: -50,  usableRange: 200) == 1000)
        #expect(ColorScoreColumn.score(forOffsetY: 9999, usableRange: 200) == 0)
    }

    @Test func degenerateRangeReturnsNilRatherThanCrashOrStick() {
        #expect(ColorScoreColumn.score(forOffsetY: 0, usableRange: 0)  == nil)
        #expect(ColorScoreColumn.score(forOffsetY: 0, usableRange: -1) == nil)
    }

    /// The literal shape of the old bug: a scroll read that never moves off
    /// zero would report 1000 for every offset. Assert distinct offsets
    /// actually produce distinct, correctly-ordered scores.
    @Test func differentOffsetsProduceDifferentScores() {
        let nearTop    = ColorScoreColumn.score(forOffsetY: 10,  usableRange: 200)
        let nearBottom = ColorScoreColumn.score(forOffsetY: 190, usableRange: 200)
        #expect(nearTop != nearBottom)
        #expect(nearTop!    > 900)
        #expect(nearBottom! < 100)
    }

    // MARK: - paddedScoreGradient()

    @Test func gradientStopsAreMonotonicallyOrdered() {
        let stops = ColorScoreColumn.paddedScoreGradient().stops
        for (a, b) in zip(stops, stops.dropFirst()) {
            #expect(a.location <= b.location)
        }
    }

    @Test func gradientPaddingIsFullyTransparent() {
        let stops = ColorScoreColumn.paddedScoreGradient().stops
        #expect(rgb(stops.first!.color).3 == 0)
        #expect(rgb(stops.last!.color).3 == 0)
    }

    /// The column scrolls hot-at-top / cold-at-bottom (matching
    /// `score(forOffsetY:usableRange:)`). If the anchor order in
    /// `paddedScoreGradient` were ever accidentally flipped, the number
    /// saved would still be correct but the color shown would be wrong —
    /// not something you'd catch just glancing at the app mid-scroll.
    @Test func gradientTopMatchesHottestAnchorBottomMatchesColdest() {
        let stops = ColorScoreColumn.paddedScoreGradient().stops
        let opaque = stops.filter { rgb($0.color).3 > 0 }
        #expect(rgb(opaque.first!.color) == rgb(ColorScale.anchors.last!.color))  // hottest
        #expect(rgb(opaque.last!.color)  == rgb(ColorScale.anchors.first!.color)) // coldest
    }
}
