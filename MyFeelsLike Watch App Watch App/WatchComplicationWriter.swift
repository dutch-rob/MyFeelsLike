// SPDX-License-Identifier: GPL-3.0-or-later
//
//  WatchComplicationWriter.swift
//  MyFeelsLike Watch App
//
//  Builds the hourly ComplicationSnapshot from a forecast and writes it to the
//  App Group, then reloads the complications. Used by both the foreground model
//  and the background refresh.
//

import Foundation
import WidgetKit

enum WatchComplicationWriter {

    static func write(current: ForecastPoint?, series10d: [ForecastPoint],
                      hasModel: Bool, useFahrenheit: Bool, sunSplit: Bool) {
        guard let snap = build(current: current, series10d: series10d,
                               hasModel: hasModel, useFahrenheit: useFahrenheit,
                               sunSplit: sunSplit) else { return }
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()   // corner + circular
    }

    /// "now" + forecast hours up to +48 h, each tagged with its day's range.
    /// `now` is injectable so tests are deterministic.
    static func build(current: ForecastPoint?, series10d: [ForecastPoint],
                      hasModel: Bool, useFahrenheit: Bool, sunSplit: Bool = false,
                      now: Date = Date()) -> ComplicationSnapshot? {
        let cal = Calendar.current
        func dayKey(_ d: Date) -> Date { cal.startOfDay(for: d) }

        var dTempMin: [Date: Double] = [:], dTempMax: [Date: Double] = [:]
        var dFeelMin: [Date: Double] = [:], dFeelMax: [Date: Double] = [:]
        for p in series10d {
            let k = dayKey(p.date)
            dTempMin[k] = min(dTempMin[k] ?? .greatestFiniteMagnitude, p.temperatureC)
            dTempMax[k] = max(dTempMax[k] ?? -.greatestFiniteMagnitude, p.temperatureC)
            if let s = p.myFeelsLikeScore {
                dFeelMin[k] = min(dFeelMin[k] ?? .greatestFiniteMagnitude, s)
                dFeelMax[k] = max(dFeelMax[k] ?? -.greatestFiniteMagnitude, s)
            }
        }

        var hours: [ForecastPoint] = []
        if let c = current { hours.append(c) }
        let cutoff = now.addingTimeInterval(48 * 3600)
        let afterNow = current?.date ?? now
        hours += series10d.filter { $0.date > afterNow && $0.date <= cutoff }

        let frames: [ComplicationFrame] = hours.map { p in
            let k = dayKey(p.date)
            let tMin = dTempMin[k] ?? p.temperatureC
            let tMax = dTempMax[k] ?? p.temperatureC
            let fMin = dFeelMin[k] ?? 0
            let fMax = dFeelMax[k] ?? 1000
            return ComplicationFrame(
                date: p.date,
                currentTempC: p.temperatureC,
                feelsCurrent: p.myFeelsLikeScore ?? (fMin + fMax) / 2,
                feelsMin: fMin, feelsMax: fMax,
                todayTempMinC: tMin, todayTempMaxC: tMax,
                feelsSun: sunSplit ? p.myFeelsLikeSunScore : nil,
                feelsShade: sunSplit ? p.myFeelsLikeShadeScore : nil)
        }
        guard !frames.isEmpty else { return nil }

        return ComplicationSnapshot(updated: Date(), useFahrenheit: useFahrenheit,
                                    hasModel: hasModel, sunSplit: sunSplit, frames: frames)
    }
}
