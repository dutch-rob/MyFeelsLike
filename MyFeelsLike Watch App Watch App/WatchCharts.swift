//
//  WatchCharts.swift
//  MyFeelsLike Watch App
//
//  Small chart helpers shared by the watch screens: the MyFeelsLike colour
//  background (positioned by time so it lines up with the curves) and a
//  compact gradient legend.
//

import SwiftUI
import Charts

/// Maximum alpha for the model-prediction background so the lines stay readable.
let watchBackgroundMaxAlpha: Double = 0.55

/// Horizontal gradient stops representing the model's predicted score at each
/// point, positioned by time within `domain`. Empty when no point has a score.
func watchFeelsBackgroundStops(_ series: [ForecastPoint],
                               domain: ClosedRange<Date>?) -> [Gradient.Stop] {
    guard series.count > 1,
          series.contains(where: { $0.myFeelsLikeScore != nil }) else { return [] }
    let lo = domain?.lowerBound ?? series.first!.date
    let hi = domain?.upperBound ?? series.last!.date
    let span = hi.timeIntervalSince(lo)
    guard span > 0 else { return [] }
    return series.compactMap { p -> Gradient.Stop? in
        guard let score = p.myFeelsLikeScore else { return nil }
        let alpha = max(0, min(1, p.myFeelsLikeOpacity)) * watchBackgroundMaxAlpha
        let color = ColorScale.color(forScore: score).opacity(alpha)
        let loc = max(0, min(1, p.date.timeIntervalSince(lo) / span))
        return Gradient.Stop(color: color, location: CGFloat(loc))
    }
}

/// MyFeelsLike colour background filling a chart's plot area, time-aligned.
@ViewBuilder
func watchFeelsChartBackground(_ proxy: ChartProxy,
                               series: [ForecastPoint],
                               domain: ClosedRange<Date>?) -> some View {
    let stops = watchFeelsBackgroundStops(series, domain: domain)
    if !stops.isEmpty {
        GeometryReader { geo in
            let frame = geo[proxy.plotAreaFrame]
            LinearGradient(gradient: Gradient(stops: stops),
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
    }
}
