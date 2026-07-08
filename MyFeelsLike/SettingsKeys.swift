//
//  SettingsKeys.swift
//  MyFeelsLike
//
//  Central home for the @AppStorage / UserDefaults keys used across the app, so
//  a key is spelled in exactly one place (a typo elsewhere can't silently split
//  a preference into two). Graph-series visibility keys live in `GraphKey`.
//

import Foundation

enum SettingsKey {
    /// Show temperatures in °F (true) or °C (false). Defaults per region on first launch.
    static let useFahrenheit     = "useFahrenheit"
    /// Show times as 12-hour (am/pm) rather than 24-hour.
    static let use12HourClock    = "use12HourClock"
    /// Whether the swipe pager includes the table screen.
    static let showTable         = "showTable"

    // Scenario the prediction is made for.
    static let scenarioActivity  = "scenarioActivity"
    static let scenarioDress     = "scenarioDress"
    static let scenarioSun       = "scenarioSun"

    /// Opt-in to anonymised CloudKit data sharing with the developer.
    static let shareDataWithDevs = "shareDataWithDevs"
    /// One-shot flag: ratings/model were wiped for the 0–1000 score migration.
    static let didWipeForScoreV1 = "didWipeForScoreV1"
}
