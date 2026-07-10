// SPDX-License-Identifier: GPL-3.0-or-later
//
//  ComplicationSnapshot.swift
//  MyFeelsLike  (shared: watch app + complication widget)
//
//  The watch app writes this to the App Group after each fetch. It holds an
//  hourly series of frames covering the next ~48 h, so the complication's
//  timeline can advance every hour from already-downloaded forecast data
//  (no new fetch needed between updates).
//

import Foundation

/// One hour's worth of complication state.
struct ComplicationFrame: Codable {
    var date: Date
    var currentTempC: Double
    /// Feels-like score (0…1000) at this hour, and the range for this hour's day.
    var feelsCurrent: Double
    var feelsMin: Double
    var feelsMax: Double
    /// This hour's day temperature range (used for the cold-start gauge).
    var todayTempMinC: Double
    var todayTempMaxC: Double
    /// In-sun / in-shade feels-like scores at this hour — set only when the
    /// model learned a sun effect. Used to split the circular complication's
    /// center disc; nil ⇒ single-color center.
    var feelsSun: Double?
    var feelsShade: Double?
}

struct ComplicationSnapshot: Codable {
    var updated: Date
    var useFahrenheit: Bool
    var hasModel: Bool
    /// Whether the model learned a sun effect (⇒ split the circular center into
    /// sun/shade). Optional so older snapshots still decode.
    var sunSplit: Bool?
    /// Hourly frames, oldest → newest (first ≈ now).
    var frames: [ComplicationFrame]

    static let appGroup = "group.robotex.MyFeelsLike"
    static let key = "complicationSnapshot"

    func save() {
        guard let store = UserDefaults(suiteName: Self.appGroup),
              let data = try? JSONEncoder().encode(self) else { return }
        store.set(data, forKey: Self.key)
    }

    static func load() -> ComplicationSnapshot? {
        guard let store = UserDefaults(suiteName: appGroup),
              let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ComplicationSnapshot.self, from: data)
    }
}
