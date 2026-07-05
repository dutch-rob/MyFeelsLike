//
//  WeatherSky.swift
//  MyFeelsLike
//
//  A painted "sky" for the current conditions, seen looking up from the
//  ground: clear blue by day, dark with stars by night, and opaque cloud
//  patches whose coverage matches the cloud fraction at each altitude (white
//  high cloud furthest back, light-grey mid, darker-grey low in front), plus
//  rain streaks when precipitating. Used as the screen backdrop (WeatherSkyView).
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
    /// Paint one weather state into `rect`, as seen looking up from the ground:
    /// a flat sky (blue by day, dark + stars by night) with opaque cloud
    /// patches. Cloud layers stack high (back) → mid → low (front), each
    /// covering its own fraction of the sky; clear gaps show the sky through.
    static func draw(_ context: GraphicsContext, rect: CGRect, point p: ForecastPoint,
                     isDay day: Bool, seed: UInt64) {
        // Flat base sky (no gradient, no altitude sectors).
        let sky = day ? Color(red: 0.46, green: 0.73, blue: 0.98) : Color(red: 0.03, green: 0.05, blue: 0.15)
        context.fill(Path(rect), with: .color(sky))

        // Stars at night, scattered across the whole sky; clouds paint over them.
        if !day {
            var rng = SeededRNG(seed: seed &+ 101)
            let n = max(6, Int(rect.width * rect.height / 2600))
            for _ in 0..<n {
                let x = rect.minX + CGFloat(rng.unit()) * rect.width
                let y = rect.minY + CGFloat(rng.unit()) * rect.height
                let s = CGFloat(0.5 + rng.unit() * 1.3)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                             with: .color(.white.opacity(0.85)))
            }
        }

        // Opaque cloud layers over the whole sky, back→front so lower cloud
        // covers higher. High ≈ white (cirrus), mid light-grey (alto), low
        // darker-grey (stratus/cumulus); dimmer at night.
        cloudLayer(context, rect, coverage: p.cloudCoverHigh,
                   color: Color(white: day ? 0.98 : 0.52), seed: seed &+ 1)
        cloudLayer(context, rect, coverage: p.cloudCoverMedium,
                   color: Color(white: day ? 0.80 : 0.40), seed: seed &+ 2)
        cloudLayer(context, rect, coverage: p.cloudCoverLow,
                   color: Color(white: day ? 0.56 : 0.28), seed: seed &+ 3)

        // Rain streaks, intensity from mm (with a nudge from probability).
        let rain = min(1.0, p.precipitationMM / 3.0 + (p.precipProbability > 0.5 ? 0.25 : 0))
        if rain > 0.03 { rainStreaks(context, rect, intensity: rain, seed: seed &+ 9) }
    }

    /// Cover ~`coverage` of the whole sky with small opaque cumulus puffs. A
    /// grid cell gets a cloud with probability `coverage`; clouds are sized to
    /// touch at full coverage (solid overcast) and leave gaps otherwise.
    private static func cloudLayer(_ context: GraphicsContext, _ rect: CGRect,
                                   coverage: Double, color: Color, seed: UInt64) {
        guard coverage > 0.02 else { return }
        var rng = SeededRNG(seed: seed)
        let cols = 16, rows = 10
        let cloudW = rect.width / CGFloat(cols) * 1.35
        for c in 0..<cols {
            for r in 0..<rows {
                let present = rng.unit() < coverage
                let jx = (Double(c) + 0.5) / Double(cols) + (rng.unit() - 0.5) * 0.6 / Double(cols)
                let jy = (Double(r) + 0.5) / Double(rows) + (rng.unit() - 0.5) * 0.6 / Double(rows)
                let sizeVar = CGFloat(0.8 + rng.unit() * 0.5)
                guard present else { continue }
                let cx = rect.minX + CGFloat(jx) * rect.width
                let cy = rect.minY + CGFloat(jy) * rect.height
                drawCumulus(context, centerX: cx, baselineY: cy, width: cloudW * sizeVar,
                            color: color, rng: &rng)
            }
        }
    }

    /// One small cumulus: a flat-bottomed base with a few rounded bulges along
    /// the top (centre bulge largest), wider than it is tall. Drawn as opaque
    /// overlapping fills in a single colour so they read as one puffy cloud.
    private static func drawCumulus(_ context: GraphicsContext, centerX cx: CGFloat,
                                    baselineY by: CGFloat, width w: CGFloat,
                                    color: Color, rng: inout SeededRNG) {
        let h = w * 0.52                       // wider than tall
        let baseH = h * 0.4
        // Flat-bottomed base slab (small corner radius → near-flat bottom edge).
        let baseRect = CGRect(x: cx - w * 0.42, y: by - baseH, width: w * 0.84, height: baseH)
        context.fill(Path(roundedRect: baseRect, cornerRadius: baseH * 0.3), with: .color(color))
        // Top bulges sitting on the base; centre puff is the largest.
        let puffs: [(dx: CGFloat, r: CGFloat)] = [(-0.27, 0.28), (0.02, 0.42), (0.29, 0.30)]
        for p in puffs {
            let rr = w * p.r * CGFloat(0.9 + rng.unit() * 0.2)
            let pcx = cx + p.dx * w
            let pcy = by - baseH * 0.55 - rr * 0.5
            context.fill(Path(ellipseIn: CGRect(x: pcx - rr, y: pcy - rr, width: rr * 2, height: rr * 2)),
                         with: .color(color))
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


/// Full-rect sky for the current conditions (screen backdrop). `isDay` is the
/// caller's day/night decision (following iOS's sunset/sunrise timing).
struct WeatherSkyView: View {
    let point: ForecastPoint?
    let isDay: Bool
    var body: some View {
        Canvas { context, size in
            guard let p = point else { return }
            SkyRenderer.draw(context, rect: CGRect(origin: .zero, size: size),
                             point: p, isDay: isDay, seed: 7)
        }
        // Rasterise once so the many cloud fills don't re-run during swipes.
        .drawingGroup()
    }
}

