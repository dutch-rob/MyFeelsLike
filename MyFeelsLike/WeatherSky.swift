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
import Charts

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

extension SkyRenderer {
    /// A single hour's sky as a solid column (used for the in-plot per-hour
    /// background). Cloud blobs would look choppy in a thin column, so cloud
    /// cover is a grey tint instead — altitude-weighted (white high, light-grey
    /// mid, darker-grey low), with alpha tracking the total cover.
    static func drawColumn(_ context: GraphicsContext, rect: CGRect, point p: ForecastPoint, seed: UInt64) {
        guard rect.width > 0.4, rect.height > 0.4 else { return }
        let day = p.isDaylight
        let top    = day ? Color(red: 0.40, green: 0.70, blue: 0.98) : Color(red: 0.02, green: 0.03, blue: 0.12)
        let bottom = day ? Color(red: 0.70, green: 0.86, blue: 1.00) : Color(red: 0.06, green: 0.07, blue: 0.20)
        context.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [top, bottom]),
            startPoint: CGPoint(x: rect.midX, y: rect.minY),
            endPoint:   CGPoint(x: rect.midX, y: rect.maxY)))

        if !day {
            var rng = SeededRNG(seed: seed &+ 55)
            let n = max(1, Int(rect.width * rect.height / 3000))
            for _ in 0..<n {
                let x = rect.minX + CGFloat(rng.unit()) * rect.width
                let y = rect.minY + CGFloat(rng.unit()) * rect.height * 0.75
                let s = CGFloat(0.5 + rng.unit() * 1.1)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                             with: .color(.white.opacity(0.8)))
            }
        }

        let cover = min(1.0, p.cloudCover)
        if cover > 0.02 {
            let low = p.cloudCoverLow, mid = p.cloudCoverMedium, high = p.cloudCoverHigh
            let tot = max(0.001, low + mid + high)
            let grey = (high * (day ? 0.98 : 0.82) + mid * (day ? 0.78 : 0.55) + low * (day ? 0.55 : 0.36)) / tot
            context.fill(Path(rect), with: .color(Color(white: grey).opacity(min(0.8, cover))))
        }

        let rain = min(1.0, p.precipitationMM / 3.0 + (p.precipProbability > 0.5 ? 0.25 : 0))
        if rain > 0.03 {
            var rng = SeededRNG(seed: seed &+ 77)
            let n = Int(Double(max(1, Int(rect.width * rect.height / 900))) * rain)
            for _ in 0..<n {
                let x = rect.minX + CGFloat(rng.unit()) * rect.width
                let y = rect.minY + CGFloat(rng.unit()) * rect.height
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x - 2, y: y + 7))
                context.stroke(path, with: .color(.white.opacity(0.4)), lineWidth: 1)
            }
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

/// Per-hour sky painted across a chart's plot area (#9). Each point owns the
/// column from its x to the next point's x.
@ViewBuilder
func perHourSkyBackground(_ proxy: ChartProxy, points: [ForecastPoint]) -> some View {
    GeometryReader { geo in
        if let plotFrame = proxy.plotFrame, points.count > 1 {
            let rect = geo[plotFrame]
            Canvas { context, _ in
                for (i, p) in points.enumerated() {
                    let x0 = CGFloat(proxy.position(forX: p.date) ?? 0)
                    let x1: CGFloat = (i + 1 < points.count)
                        ? CGFloat(proxy.position(forX: points[i + 1].date) ?? x0)
                        : rect.width
                    let left = rect.minX + Swift.min(x0, x1)
                    let width = Swift.max(0, abs(x1 - x0))
                    SkyRenderer.drawColumn(context,
                        rect: CGRect(x: left, y: rect.minY, width: width, height: rect.height),
                        point: p, seed: UInt64(i + 1))
                }
            }
        }
    }
}
