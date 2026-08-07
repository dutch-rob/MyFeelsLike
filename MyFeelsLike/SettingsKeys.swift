// SPDX-License-Identifier: GPL-3.0-or-later
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
    /// The name shown to others when comparing nearby (else the device name).
    static let compareName       = "compareName"
    /// One-shot: we've already prompted for a compare name on first Compare use.
    static let didAskCompareName = "didAskCompareName"
    /// Last app version whose welcome / what's-new sheet was shown ("" = never).
    static let lastSeenVersion   = "lastSeenVersion"
    /// How in-shade vs in-sun is drawn: SunShadeStyle raw value ("separate"/"gradient").
    static let sunShadeStyle     = "sunShadeStyle"
    /// How the temperature / precip / wind curves are drawn: ChartSeriesStyle raw
    /// value ("area" filled bands, or "lines" — thin curves, no fill; in lines
    /// mode the precip/wind panel reads bottom-up like the temperature panel).
    static let chartSeriesStyle  = "chartSeriesStyle"
    /// Saturation of the weather series colors: GraphPalette raw value ("vivid"
    /// full-strength, or "muted" softened for people who find them too harsh).
    /// Does not touch the MyFeelsLike score colors.
    static let graphPalette      = "graphPalette"
    /// Experimental: replace the paged 24h/10-day screens with one continuous
    /// timeline that morphs between them (the color band folds into the heat map
    /// while the charts zoom). Off by default.
    static let useFoldTimeline   = "useFoldTimeline"
    /// Remembers the "Table screen" setting from just before Fold timeline was
    /// turned on (fold mode force-hides the table), so it can be restored when
    /// fold mode is turned back off.
    static let tableBeforeFold   = "tableBeforeFold"
    /// Publish your model so others can compare with you (default on). Off keeps
    /// you able to see others while withdrawing your own shared model.
    static let shareForCompare   = "shareForCompare"
    /// Sync ratings + model across the user's own devices via iCloud (default
    /// off). Read once at launch to pick the SwiftData CloudKit configuration.
    static let syncAcrossDevices = "syncAcrossDevices"

    // Scenario the prediction is made for.
    static let scenarioActivity  = "scenarioActivity"
    static let scenarioDress     = "scenarioDress"
    static let scenarioSun       = "scenarioSun"

    /// Opt-in to anonymised CloudKit data sharing with the developer.
    static let shareDataWithDevs = "shareDataWithDevs"
    /// One-shot flag: ratings/model were wiped for the 0–1000 score migration.
    static let didWipeForScoreV1 = "didWipeForScoreV1"
    /// One-shot flag: existing ratings were converted from the previous color
    /// scale to the redesigned one (see ScoreScaleMigration). Set for fresh
    /// installs too, so a new user never runs the conversion.
    static let didMigrateScoreScaleV2 = "didMigrateScoreScaleV2"
    /// One-shot repair. A build shipped in which the conversion above ran but
    /// did not clear the developer-upload markers, so converted ratings were
    /// never re-sent and their uploaded copies kept old-scale scores with no
    /// score1. Anyone who installed that build has the migration flag set, so
    /// the fixed migration path can no longer help them — this forces one
    /// re-upload regardless of whether they migrated.
    static let didReuploadAfterScaleV2 = "didReuploadAfterScaleV2"
}
