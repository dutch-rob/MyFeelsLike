//
//  ComplicationSnapshot.swift
//  MyFeelsLike  (shared: watch app + complication widget)
//
//  Compact state the watch app writes to the App Group after each weather
//  fetch; the complication's timeline provider reads it. Holds everything the
//  corner complication needs without the widget having to fetch or predict.
//

import Foundation

struct ComplicationSnapshot: Codable {
    var updated: Date
    /// Current temperature in Celsius (formatted per `useFahrenheit`).
    var currentTempC: Double
    var useFahrenheit: Bool
    /// True when a personalised feels-like model exists; drives whether the
    /// gauge shows the feels-like colour gradient or a plain temperature range.
    var hasModel: Bool
    /// Today's temperature range (used for the cold-start gauge).
    var todayTempMinC: Double
    var todayTempMaxC: Double
    /// Today's feels-like score range + current (0…1000), valid when hasModel.
    var feelsMin: Double
    var feelsMax: Double
    var feelsCurrent: Double

    static let appGroup = "group.robotex.MyFeelsLike"
    static let key = "complicationSnapshot"

    /// Current temperature rounded for display, in the user's unit.
    var currentTempDisplay: Int {
        let t = useFahrenheit ? currentTempC * 9.0 / 5.0 + 32.0 : currentTempC
        return Int(t.rounded())
    }

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
