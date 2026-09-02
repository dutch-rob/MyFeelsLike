// SPDX-License-Identifier: GPL-3.0-or-later
//
//  ColorScale.swift
//  MyFeelsLike
//
//  Vertical color-gradient temperature scale used on the Rate Feels Like
//  screen. Domain is Celsius; the same gradient is reused with Fahrenheit
//  tick labels via simple unit conversion.
//
//  Anchors (°C → RGB):
//      −20 white   (1, 1, 1)
//        9 blue    (0, 0, 1)         — derived: 90% green / 10% blue at 18°C
//       21 green   (0, 1, 0)
//    27.25 yellow  (1, 1, 0)         — derived: 80% yellow / 20% green at 26°C
//       33 red     (1, 0, 0)
//       39 purple  (1, 0, 1)
//       45 black   (0, 0, 0)
//
//  Below −20 stays white; above 45 stays black (clamped).
//

import SwiftUI

enum ColorScale {

    static let minC: Double = -20
    static let maxC: Double = 45

    struct Anchor {
        let tempC: Double
        let color: Color
    }

    static let anchors: [Anchor] = [
        Anchor(tempC: -20.00, color: Color(red: 1, green: 1, blue: 1)),  // white
        Anchor(tempC:   9.00, color: Color(red: 0, green: 0, blue: 1)),  // blue
        Anchor(tempC:  21.00, color: Color(red: 0, green: 1, blue: 0)),  // green
        Anchor(tempC:  27.25, color: Color(red: 1, green: 1, blue: 0)),  // yellow
        Anchor(tempC:  33.00, color: Color(red: 1, green: 0, blue: 0)),  // red
        Anchor(tempC:  39.00, color: Color(red: 1, green: 0, blue: 1)),  // purple
        Anchor(tempC:  45.00, color: Color(red: 0, green: 0, blue: 0))   // black
    ]

    /// SwiftUI gradient covering the full [minC, maxC] domain.
    static var gradient: Gradient {
        let span = maxC - minC
        return Gradient(stops: anchors.map { a in
            Gradient.Stop(
                color: a.color,
                location: CGFloat((a.tempC - minC) / span)
            )
        })
    }

    /// Interpolated color at an arbitrary temperature (clamped to scale).
    static func color(forC tempC: Double) -> Color {
        let t = max(minC, min(maxC, tempC))
        // Find bracketing anchors.
        guard let upperIdx = anchors.firstIndex(where: { $0.tempC >= t }) else {
            return anchors.last!.color
        }
        if upperIdx == 0 { return anchors.first!.color }
        let lo = anchors[upperIdx - 1]
        let hi = anchors[upperIdx]
        let span = hi.tempC - lo.tempC
        let frac = span > 0 ? (t - lo.tempC) / span : 0
        let (r1, g1, b1) = rgb(lo.color)
        let (r2, g2, b2) = rgb(hi.color)
        return Color(
            red:   r1 + (r2 - r1) * frac,
            green: g1 + (g2 - g1) * frac,
            blue:  b1 + (b2 - b1) * frac
        )
    }

    private static func rgb(_ c: Color) -> (Double, Double, Double) {
        // Resolve via UIColor for a stable RGB tuple.
        let ui = UIColor(c)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    // MARK: - Score-based scale (0…1000)
    //
    // The app now expresses "feels like" as a pure color on a 0…1000 scale —
    // no temperature units exposed to the user. Anchor colors from the
    // temperature scale are reused, but distributed evenly across [0, 1000].

    static let minScore: Double = 0
    static let maxScore: Double = 1000

    /// Power-curve exponent for the *legacy* score scale (see legacyColor).
    static let scoreGradientExponent: Double = 0.6

    // MARK: The score palette
    //
    // Redesigned from tester feedback: fewer, more distinguishable colors, with
    // green in the middle of the scale rather than low on it. Cold→hot runs
    // white → blue → green → yellow → red → dark red, and because the anchors
    // carry explicit score positions there is no power warp to keep in sync —
    // the rating column and the forecast colors read straight off this list.

    struct ScoreAnchor {
        let score: Double
        let color: Color
    }

    static let scoreAnchors: [ScoreAnchor] = [
        ScoreAnchor(score:    0, color: Color(red: 1.00, green: 1.00, blue: 1.00)),  // white
        ScoreAnchor(score:  250, color: Color(red: 0.00, green: 0.00, blue: 1.00)),  // blue
        // Two anchors through the blue-to-green stretch. Interpolating straight
        // from blue to green in gamma-encoded sRGB loses more blue luminance
        // than it gains in green at first, so the scale used to grow slightly
        // *darker* just past blue (relative luminance 0.072 at 250, 0.064 at
        // 275, still 0.067 at 300) and its midpoint teal sat at 0.17 where an
        // even ramp wants 0.39. These two put luminance on a straight line from
        // blue to green, so the only darkening left is at the hot end, where it
        // carries meaning. Blue, green and yellow do not move, so the
        // proportions of the scale are unchanged.
        ScoreAnchor(score:  333, color: Color(red: 0.00, green: 0.61, blue: 0.85)),  // azure
        ScoreAnchor(score:  417, color: Color(red: 0.00, green: 0.85, blue: 0.45)),  // spring green
        ScoreAnchor(score:  500, color: Color(red: 0.00, green: 1.00, blue: 0.00)),  // green
        ScoreAnchor(score:  690, color: Color(red: 1.00, green: 1.00, blue: 0.00)),  // yellow
        ScoreAnchor(score:  880, color: Color(red: 1.00, green: 0.00, blue: 0.00)),  // red
        ScoreAnchor(score: 1000, color: Color(red: 0.45, green: 0.00, blue: 0.00))   // dark red
    ]

    // MARK: - Color vision

    /// How the comfort scale is expressed, for people whose color vision makes
    /// the default palette hard to read.
    ///
    /// `full` is the designed palette. `noRed` keeps every color up to pure
    /// yellow exactly where it is and replaces the red end with yellow
    /// darkening to black — red/green confusion (deuteranomaly and
    /// protanomaly, by far the most common deficiencies) then cannot turn the
    /// hot end into the mild end, because the remaining cue is lightness.
    /// `noColor` removes hue as a carrier of meaning altogether: the scale is
    /// grayscale, and the screens that lean on color switch to named comfort
    /// categories and line patterns instead.
    enum ColorVisionMode: String, CaseIterable {
        case full
        case noRed
        case noColor
    }

    /// How `noColor` mode replaces the comfort color bar. Both keep the same
    /// meaning; they differ in shape. `lineGraph` redraws comfort as a
    /// conventional curve against named categories. `grayBars` keeps the bar
    /// exactly where it is — same layout, same rotation on the rating column —
    /// and simply renders it in shades of gray.
    enum NoColorStyle: String, CaseIterable {
        case lineGraph
        case grayBars
    }

    static var noColorStyle: NoColorStyle {
        NoColorStyle(rawValue: UserDefaults.standard.string(forKey: "noColorStyle") ?? "")
            ?? .lineGraph
    }

    /// True when comfort should be drawn as a curve rather than a bar.
    static var usesComfortLineGraph: Bool {
        visionMode == .noColor && noColorStyle == .lineGraph
    }

    /// Read straight from user defaults rather than passed down the view tree:
    /// this type is a pile of static functions called from charts, the
    /// complication and the rating column alike, and threading a mode through
    /// every one of them would touch far more code than it is worth. Views that
    /// need to redraw on a change hold their own @AppStorage for the same key.
    static var visionMode: ColorVisionMode {
        ColorVisionMode(rawValue: UserDefaults.standard.string(forKey: "colorVisionMode") ?? "")
            ?? .full
    }

    /// Red removed: identical to `scoreAnchors` up to pure yellow, then yellow
    /// darkens to black instead of turning red. Keeping the shared anchors in
    /// place means a rating made in one mode means the same in the other.
    static let noRedScoreAnchors: [ScoreAnchor] = [
        ScoreAnchor(score:    0, color: Color(red: 1.00, green: 1.00, blue: 1.00)),  // white
        ScoreAnchor(score:  250, color: Color(red: 0.00, green: 0.00, blue: 1.00)),  // blue
        // Same two as the full palette; they matter more here, since this
        // encoding leans on lightness to separate hot from mild.
        ScoreAnchor(score:  333, color: Color(red: 0.00, green: 0.61, blue: 0.85)),  // azure
        ScoreAnchor(score:  417, color: Color(red: 0.00, green: 0.85, blue: 0.45)),  // spring green
        ScoreAnchor(score:  500, color: Color(red: 0.00, green: 1.00, blue: 0.00)),  // green
        ScoreAnchor(score:  690, color: Color(red: 1.00, green: 1.00, blue: 0.00)),  // yellow
        ScoreAnchor(score: 1000, color: Color(red: 0.00, green: 0.00, blue: 0.00))   // black
    ]

    /// Grayscale: light at the cold end, dark at the hot end. Used where a
    /// color still has to be produced in `noColor` mode (the complication, for
    /// instance) so magnitude survives even when hue carries nothing.
    static let grayScoreAnchors: [ScoreAnchor] = [
        ScoreAnchor(score:    0, color: Color(white: 1.00)),
        ScoreAnchor(score: 1000, color: Color(white: 0.10))
    ]

    /// The anchors in force for the current setting.
    static var activeScoreAnchors: [ScoreAnchor] {
        switch visionMode {
        case .full:    return scoreAnchors
        case .noRed:   return noRedScoreAnchors
        case .noColor: return grayScoreAnchors
        }
    }

    // MARK: - Named comfort categories
    //
    // The same scale said in words, for `noColor` mode and for anyone who would
    // rather read a label than a hue. Positions are the color anchors, so the
    // words and the colors always mean the same thing.

    struct ComfortCategory {
        let score: Double
        let name: String
    }

    static let comfortCategories: [ComfortCategory] = [
        ComfortCategory(score:    0, name: "very cold"),
        ComfortCategory(score:  250, name: "cold"),
        ComfortCategory(score:  500, name: "mild"),
        ComfortCategory(score:  690, name: "warm"),
        ComfortCategory(score:  880, name: "very warm"),
        ComfortCategory(score: 1000, name: "hot")
    ]

    /// The category a score reads as: the nearest anchor, so a score exactly
    /// between two categories takes the lower one.
    static func categoryName(forScore score: Double) -> String {
        let s = score.isFinite ? max(minScore, min(maxScore, score)) : minScore
        var best = comfortCategories[0]
        var bestGap = Double.infinity
        for c in comfortCategories {
            let gap = abs(c.score - s)
            if gap < bestGap { bestGap = gap; best = c }
        }
        return best.name
    }

    /// Color at an arbitrary score (clamped to [0, 1000]), interpolating between
    /// the `scoreAnchors`. This is the single source for every MyFeelsLike color
    /// — band, heatmap, complication and the rating column alike.
    static func color(forScore score: Double) -> Color {
        let s = score.isFinite ? max(minScore, min(maxScore, score)) : minScore
        // Find the bracketing anchors by score position.
        let palette = activeScoreAnchors
        guard let hiIdx = palette.firstIndex(where: { $0.score >= s }) else {
            return palette.last!.color
        }
        if hiIdx == 0 { return palette.first!.color }
        let lo = palette[hiIdx - 1], hi = palette[hiIdx]
        let span = hi.score - lo.score
        let t = span > 0 ? (s - lo.score) / span : 0
        let (r1, g1, b1) = rgb(lo.color)
        let (r2, g2, b2) = rgb(hi.color)
        return Color(red:   r1 + (r2 - r1) * t,
                     green: g1 + (g2 - g1) * t,
                     blue:  b1 + (b2 - b1) * t)
    }

    /// The previous palette, kept only so the rating column can show old and new
    /// side by side while testers compare them. Remove with that comparison.
    static func legacyColor(forScore score: Double) -> Color {
        let m = Double(anchors.count - 1)
        // A non-finite score (from a degenerate fit) would otherwise propagate
        // NaN into the returned Color and on into CoreGraphics.
        let s = score.isFinite ? max(minScore, min(maxScore, score)) : minScore
        // g: 0 at the hottest end (score 1000), 1 at the coldest (score 0).
        let g = 1 - s / maxScore
        let rev = anchors.reversed().map { $0.color }   // black(hot) … white(cold)
        // Anchor j sits at position pow(j/m, exponent). Find the bracketing
        // pair for g and interpolate linearly in position (as LinearGradient).
        let lo = max(0, min(Int(m) - 1, Int(m * pow(g, 1 / scoreGradientExponent))))
        let locLo = pow(Double(lo) / m, scoreGradientExponent)
        let locHi = pow(Double(lo + 1) / m, scoreGradientExponent)
        let t = locHi > locLo ? max(0, min(1, (g - locLo) / (locHi - locLo))) : 0
        let (r1, g1, b1) = rgb(rev[lo])
        let (r2, g2, b2) = rgb(rev[lo + 1])
        return Color(
            red:   r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue:  b1 + (b2 - b1) * t
        )
    }

    /// True when `color(forScore:)` is light enough to prefer black text on it.
    static func isLight(forScore score: Double) -> Bool {
        let (r, g, b) = rgb(color(forScore: score))
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.55
    }

    /// Black or white, whichever contrasts better with `color(forScore:)`.
    static func contrastingText(forScore score: Double) -> Color {
        isLight(forScore: score) ? .black : .white
    }

    /// A MyFeelsLike cell/band color: the score's color, its `opacity`
    /// carrying prediction reliability (clamped to at least `floor`), or a
    /// neutral gray when there's no score. The single source for the color
    /// used by every MyFeelsLike band, heatmap and complication center.
    static func feelsColor(score: Double?, opacity: Double = 1, floor: Double = 0.25) -> Color {
        guard let score, score.isFinite else { return Color.gray.opacity(0.25) }
        let a = opacity.isFinite ? opacity : 1          // guard NaN → CoreGraphics
        return color(forScore: score).opacity(max(floor, min(1, a)))
    }
}

// Convenience temperature conversions.
enum TempUnit {
    static func cToF(_ c: Double) -> Double { c * 9.0 / 5.0 + 32.0 }
    static func fToC(_ f: Double) -> Double { (f - 32.0) * 5.0 / 9.0 }
}
