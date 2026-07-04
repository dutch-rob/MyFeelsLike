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

    /// Power-curve exponent that spaces the colour anchors on the Rate Feels
    /// Like column (RateFeelsLikeView.paddedScoreGradient), giving the dark
    /// black→purple end more room. `color(forScore:)` applies the identical
    /// warp so the colour shown for a forecast score is exactly the colour the
    /// user saw under the indicator when they recorded that score. Shared here
    /// so the two mappings can't drift apart.
    static let scoreGradientExponent: Double = 0.6

    /// Color at an arbitrary score (clamped to [0, 1000]).
    ///
    /// Must match the rating column: there the anchors run hot→cold top→bottom
    /// (score 1000 = black at the top, 0 = white at the bottom) and are spaced
    /// by `scoreGradientExponent`, with the gradient interpolating linearly in
    /// position between adjacent anchors. We reproduce that placement exactly.
    static func color(forScore score: Double) -> Color {
        let m = Double(anchors.count - 1)
        let s = max(minScore, min(maxScore, score))
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

    /// Black or white, whichever contrasts better with `color(forScore:)`.
    static func contrastingText(forScore score: Double) -> Color {
        let (r, g, b) = rgb(color(forScore: score))
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.55 ? .black : .white
    }
}

// Convenience temperature conversions.
enum TempUnit {
    static func cToF(_ c: Double) -> Double { c * 9.0 / 5.0 + 32.0 }
    static func fToC(_ f: Double) -> Double { (f - 32.0) * 5.0 / 9.0 }
}
