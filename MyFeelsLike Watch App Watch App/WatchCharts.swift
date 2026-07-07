//
//  WatchCharts.swift
//  MyFeelsLike Watch App
//
//  Small chart helpers shared by the watch screens: the MyFeelsLike colour
//  for the band/heatmap cells, plus shared axis styling.
//

import SwiftUI
import Charts

/// Cell colour for the MyFeelsLike colour band / heatmap: the score's colour,
/// its opacity carrying prediction reliability. Grey when there's no score.
func watchHeatColor(_ p: ForecastPoint) -> Color {
    guard let s = p.myFeelsLikeScore else { return Color.gray.opacity(0.25) }
    let alpha = max(0.25, min(1, p.myFeelsLikeOpacity))
    return ColorScale.color(forScore: s).opacity(alpha)
}

/// Colour for a split sun/shade band cell from an explicit score + reliability.
func watchScoreColor(_ score: Double?, opacity: Double) -> Color {
    guard let s = score else { return Color.gray.opacity(0.25) }
    return ColorScale.color(forScore: s).opacity(max(0.2, min(1, opacity)))
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
