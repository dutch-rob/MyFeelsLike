// SPDX-License-Identifier: GPL-3.0-or-later
//
//  HeatmapFoldDemo.swift
//  MyFeelsLike
//
//  PROTOTYPE (experimental, reachable from Settings) for the "scripted fold":
//  a canned animation that folds the 24-hour MyFeelsLike color bar up into the
//  10-day time-of-day heatmap, to show newcomers how the heatmap is built.
//
//  The morph is hand-drawn in a Canvas (Swift Charts can't draw a cell at an
//  angle). A single progress value t drives it: t=0 is the flat 24-hour bar
//  (one day, full width); t=1 is the heatmap (N day-columns). Each day's row of
//  24 hourly cells swings from horizontal to vertical about the day's centre —
//  the literal "fold" — while the view zooms out so more days come into view.
//
//  This is a feel-test, not the production transition: it uses synthesized
//  scores and is not wired into the real 24h↔10-day swipe.
//

import SwiftUI

// MARK: - The morph itself

/// Renders the fold at an arbitrary progress `t` (0 = flat 24-hour bar,
/// 1 = full heatmap). `scores[day][hour]` are 0…1000 MyFeelsLike scores.
struct HeatmapFoldView: View {
    let scores: [[Double]]     // [day][hour], hour 0…23
    var t: Double              // 0…1

    private var dayCount: Int { max(1, scores.count) }
    private let hours = 24

    var body: some View {
        Canvas { ctx, size in
            let gutter: CGFloat = 22           // left space for the y labels
            let plotW = size.width - gutter
            let midY = size.height / 2
            let bandH = size.height * 0.9      // heatmap column height at t=1
            let barTh = min(28, size.height * 0.32)   // flat-bar thickness at t=0

            // How many days are in view: 1 at t=0, all of them by t≈0.6.
            let vis = 1 + Double(dayCount - 1) * min(1, t / 0.6)
            let colW = plotW / CGFloat(vis)

            for d in 0..<dayCount {
                let f = foldProgress(day: d)
                if f <= 0 && d > 0 { continue }         // not yet arrived
                let phi = f * .pi / 2                    // 0 → 90°
                let dir = CGVector(dx: cos(phi), dy: -sin(phi))   // right → up
                let colCenterX = gutter + (CGFloat(d) + 0.5) * colW
                let length = lerp(colW, bandH, f)       // hours spread along this
                let alongSize = length / CGFloat(hours) // per-cell extent along strip
                let crossSize = lerp(barTh, colW, f)    // per-cell extent across strip

                for h in 0..<hours {
                    let s = (Double(h) + 0.5) / Double(hours) - 0.5   // -0.5…0.5, centred
                    let cx = colCenterX + CGFloat(s) * length * dir.dx
                    let cy = midY + CGFloat(s) * length * dir.dy
                    let color = ColorScale.color(forScore: scores[d][h])

                    ctx.drawLayer { layer in
                        layer.translateBy(x: cx, y: cy)
                        layer.rotate(by: .radians(phi))
                        let rect = CGRect(x: -alongSize / 2, y: -crossSize / 2,
                                          width: alongSize, height: crossSize)
                        layer.fill(Path(rect), with: .color(color))
                    }
                }
            }

            // Faint hour guides that fade in as the bar becomes a grid.
            if t > 0.35 {
                let a = Double((t - 0.35) / 0.65)
                for label in [(0, "12"), (6, "6"), (12, "noon"), (18, "6"), (24, "12")] {
                    let y = midY + bandH / 2 - bandH * CGFloat(label.0) / 24
                    ctx.draw(Text(label.1).font(.system(size: 9)).foregroundColor(.secondary.opacity(a)),
                             at: CGPoint(x: gutter / 2, y: y), anchor: .center)
                }
            }
        }
    }

    /// Per-day fold amount at the current `t`. Earlier days fold first (staggered
    /// left→right) and every day is fully folded by t=1.
    private func foldProgress(day d: Int) -> Double {
        guard dayCount > 1 else { return smoothstep(t) }
        let appear = 0.55 * Double(d) / Double(dayCount - 1)   // 0 … 0.55
        return smoothstep(clamp((t - appear) / 0.4, 0, 1))
    }
}

// MARK: - Demo wrapper (play / replay / scrub)

struct HeatmapFoldDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var t: Double = 0
    @State private var manual = false

    private let days = 5
    private let scores: [[Double]]

    init() {
        // Synthesize a plausible day/night pattern so the heatmap has visible
        // structure: cooler (lower) overnight, warmer (higher) mid-afternoon,
        // drifting a little day to day.
        var grid: [[Double]] = []
        for d in 0..<5 {
            var day: [Double] = []
            for h in 0..<24 {
                let diurnal = sin((Double(h) - 9) / 24 * 2 * .pi)   // peak ~15:00
                let base = 480.0 + Double(d) * 22
                day.append(min(1000, max(0, base + diurnal * 300)))
            }
            grid.append(day)
        }
        scores = grid
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Watch the 24-hour color bar fold up into the 10-day heat map. Each day's 24 hours swing from side-to-side into a top-to-bottom column — which is exactly how the heat map is laid out.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                HeatmapFoldView(scores: scores, t: t)
                    .frame(height: 200)
                    .padding(.horizontal)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                HStack {
                    Text(t < 0.02 ? "24-hour bar" : t > 0.98 ? "10-day heat map" : "folding…")
                        .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        manual = false
                        t = 0
                        withAnimation(.easeInOut(duration: 2.4)) { t = 1 }
                    } label: { Label("Play fold", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Scrub").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $t, in: 0...1) { editing in if editing { manual = true } }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Heat-map fold (preview)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                // Auto-play once so the effect is seen immediately.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if !manual { withAnimation(.easeInOut(duration: 2.4)) { t = 1 } }
                }
            }
        }
    }
}

// MARK: - Small helpers

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
    a + (b - a) * CGFloat(t)
}
private func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, x)) }
private func smoothstep(_ x: Double) -> Double {
    let c = clamp(x, 0, 1)
    return c * c * (3 - 2 * c)
}

#Preview { HeatmapFoldDemoView() }
