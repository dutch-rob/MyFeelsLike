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

// MARK: - Shared axis styling
//
// Prominent gridlines, drawn at a finer interval than the labels (e.g. labels
// every 10°, gridlines every 5°). Font size on axis labels IS honoured (unlike
// the top-bar title).

private let gridLine = StrokeStyle(lineWidth: 0.5)
private let gridFine = Color.gray.opacity(0.3)
private let gridBold = Color.gray.opacity(0.6)
private let axisLabelFont = Font.system(size: 13)

/// Temperature y-axis: gridlines twice as dense as labels.
@AxisContentBuilder
func tempYAxis(useF: Bool) -> some AxisContent {
    let gridStride: Double  = useF ? 5  : 2.5
    let labelStride: Double = useF ? 10 : 5
    AxisMarks(position: .leading, values: .stride(by: gridStride)) {
        AxisGridLine(stroke: gridLine).foregroundStyle(gridBold)
    }
    AxisMarks(position: .leading, values: .stride(by: labelStride)) {
        AxisValueLabel().font(axisLabelFont)
    }
}

/// Generic (wind/precip) y-axis: prominent gridlines at the default ticks.
@AxisContentBuilder
func plainYAxis() -> some AxisContent {
    AxisMarks(position: .leading) { _ in
        AxisGridLine(stroke: gridLine).foregroundStyle(gridBold)
        AxisValueLabel().font(axisLabelFont)
    }
}

/// 24-hour x-axis: faint gridlines every 3 h, labelled bold gridlines every 6 h.
@AxisContentBuilder
func hourlyXAxis() -> some AxisContent {
    AxisMarks(values: .stride(by: .hour, count: 3)) {
        AxisGridLine(stroke: gridLine).foregroundStyle(gridFine)
    }
    AxisMarks(values: .stride(by: .hour, count: 6)) {
        AxisGridLine(stroke: gridLine).foregroundStyle(gridBold)
        AxisValueLabel(format: .dateTime.hour()).font(axisLabelFont)
    }
}

/// 10-day x-axis: faint gridlines every day, labelled bold gridlines every 2.
@AxisContentBuilder
func dailyXAxis() -> some AxisContent {
    AxisMarks(values: .stride(by: .day, count: 1)) {
        AxisGridLine(stroke: gridLine).foregroundStyle(gridFine)
    }
    AxisMarks(values: .stride(by: .day, count: 2)) {
        AxisGridLine(stroke: gridLine).foregroundStyle(gridBold)
        AxisValueLabel(format: .dateTime.weekday()).font(axisLabelFont)
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
