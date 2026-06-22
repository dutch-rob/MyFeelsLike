//
//  WatchSyncPayload.swift
//  MyFeelsLike  (shared: iOS app + watch app)
//
//  The small bundle of state the phone pushes to the watch over
//  WatchConnectivity: the trained regression model plus display settings.
//  The watch fetches its own weather, so no forecast data travels here.
//

import Foundation

struct WatchSyncPayload: Codable {
    var regressionState: RegressionState?
    var useFahrenheit: Bool
    var scenarioActivity: Int
    var scenarioDress: Int
    var scenarioSun: Int

    var scenario: Scenario {
        Scenario(activity: scenarioActivity, dress: scenarioDress, sun: scenarioSun)
    }
}

extension WatchSyncPayload {
    /// Encode for WCSession application context (a [String: Any] dictionary).
    func asApplicationContext() -> [String: Any] {
        let data = (try? JSONEncoder().encode(self)) ?? Data()
        return ["payload": data]
    }

    static func from(applicationContext context: [String: Any]) -> WatchSyncPayload? {
        guard let data = context["payload"] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchSyncPayload.self, from: data)
    }
}
