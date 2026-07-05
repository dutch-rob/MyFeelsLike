//
//  WeatherSky.swift
//  MyFeelsLike
//
//  A painted "sky" that represents a weather state: clear blue by day, dark
//  with stars by night, grey cloud patches whose coverage matches the cloud
//  fraction (white high cloud, light-grey mid, darker-grey low), and rain
//  streaks when it's precipitating. Used two ways:
//    • as the screen backdrop for the current conditions (WeatherSkyView), and
//    • per forecast hour inside a chart's plot area (see the chart backgrounds).
//

import SwiftUI

/// Small deterministic RNG so the sky doesn't shimmer when the view redraws.
struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
    mutating func unit() -> Double { Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0) }
}

enum SkyRenderer {
    /// Paint one weather state into `rect`. `seed` keeps random elements stable.
    static func draw(_ context: GraphicsContext, rect: CGRect, point p: ForecastPoint, seed: UInt64) {
        let day = p.isDaylight

        // Base sky gradient.
        let top    = day ? Color(red: 0.40, green: 0.70, blue: 0.98) : Color(red: 0.02, green: 0.03, blue: 0.12)
        let bottom = day ? Color(red: 0.70, green: 0.86, blue: 1.00) : Color(red: 0.06, green: 0.07, blue: 0.20)
        context.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [top, bottom]),
            startPoint: CGPoint(x: rect.midX, y: rect.minY),
            endPoint:   CGPoint(x: rect.midX, y: rect.maxY)))

        // Stars at night (upper portion; clouds paint over them).
        if !day {
            var rng = SeededRNG(seed: seed &+ 101)
            let n = max(6, Int(rect.width * rect.height / 2600))
            for _ in 0..<n {
                let x = rect.minX + CGFloat(rng.unit()) * rect.width
                let y = rect.minY + CGFloat(rng.unit()) * rect.height * 0.75
                let s = CGFloat(0.5 + rng.unit() * 1.3)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                             with: .color(.white.opacity(0.85)))
            }
        }

        // Cloud layers, back→front: high (white, upper) → mid → low (dark, lower).
        cloudLayer(context, rect, coverage: p.cloudCoverHigh,
                   color: Color(white: day ? 0.98 : 0.82), yLo: 0.04, yHi: 0.46, blob: 0.11, seed: seed &+ 1)
        cloudLayer(context, rect, coverage: p.cloudCoverMedium,
                   color: Color(white: day ? 0.80 : 0.55), yLo: 0.26, yHi: 0.68, blob: 0.13, seed: seed &+ 2)
        cloudLayer(context, rect, coverage: p.cloudCoverLow,
                   color: Color(white: day ? 0.58 : 0.38), yLo: 0.50, yHi: 0.94, blob: 0.16, seed: seed &+ 3)

        // Rain streaks, intensity from mm (with a nudge from probability).
        let rain = min(1.0, p.precipitationMM / 3.0 + (p.precipProbability > 0.5 ? 0.25 : 0))
        if rain > 0.03 { rainStreaks(context, rect, intensity: rain, seed: seed &+ 9) }
    }

    /// Fill roughly `coverage` of a horizontal band with soft cloud blobs.
    private static func cloudLayer(_ context: GraphicsContext, _ rect: CGRect,
                                   coverage: Double, color: Color,
                                   yLo: Double, yHi: Double, blob: Double, seed: UInt64) {
        guard coverage > 0.02 else { return }
        var rng = SeededRNG(seed: seed)
        let cols = 10, rows = 4
        for c in 0..<cols {
            for r in 0..<rows {
                let present = rng.unit() < coverage
                let jx = (Double(c) + 0.5) / Double(cols) + (rng.unit() - 0.5) * 0.06
                let jy = yLo + (Double(r) + 0.5) / Double(rows) * (yHi - yLo) + (rng.unit() - 0.5) * 0.04
                let scale = 0.8 + rng.unit() * 0.7
                guard present else { continue }
                let rad = CGFloat(blob) * rect.width * CGFloat(scale)
                let cx = rect.minX + CGFloat(jx) * rect.width
                let cy = rect.minY + CGFloat(jy) * rect.height
                context.fill(
                    Path(ellipseIn: CGRect(x: cx - rad, y: cy - rad * 0.62, width: rad * 2, height: rad * 1.24)),
                    with: .color(color.opacity(0.55)))
            }
        }
    }

    private static func rainStreaks(_ context: GraphicsContext, _ rect: CGRect,
                                    intensity: Double, seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        let n = Int(Double(Int(rect.width * rect.height / 1500)) * intensity)
        for _ in 0..<max(0, n) {
            let x = rect.minX + CGFloat(rng.unit()) * rect.width
            let y = rect.minY + CGFloat(rng.unit()) * rect.height
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x - 2.5, y: y + 9))
            context.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 1)
        }
    }
}


/// Full-rect sky for the current conditions (screen backdrop).
struct WeatherSkyView: View {
    let point: ForecastPoint?
    var body: some View {
        Canvas { context, size in
            guard let p = point else { return }
            SkyRenderer.draw(context, rect: CGRect(origin: .zero, size: size), point: p, seed: 7)
        }
    }
}

