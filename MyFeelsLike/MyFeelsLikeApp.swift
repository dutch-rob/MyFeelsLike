// SPDX-License-Identifier: GPL-3.0-or-later
//
//  MyFeelsLikeApp.swift
//  MyFeelsLike
//

import SwiftUI
import SwiftData

@main
struct MyFeelsLikeApp: App {

    init() {
        // On first launch only: choose °F or °C based on the device region.
        let fahrenheitRegions: Set<String> = [
            "US", "PR", "GU", "VI",   // United States & territories
            "BS",                      // Bahamas
            "BZ",                      // Belize
            "KY",                      // Cayman Islands
            "PW",                      // Palau
            "FM",                      // Federated States of Micronesia
            "MH"                       // Marshall Islands
        ]
        // Same regions get 12-hour (am/pm) time by default.
        let region = Locale.current.region?.identifier ?? ""
        let usImperial = fahrenheitRegions.contains(region)
        if UserDefaults.standard.object(forKey: SettingsKey.useFahrenheit) == nil {
            UserDefaults.standard.set(usImperial, forKey: SettingsKey.useFahrenheit)
        }
        if UserDefaults.standard.object(forKey: SettingsKey.use12HourClock) == nil {
            UserDefaults.standard.set(usImperial, forKey: SettingsKey.use12HourClock)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(Self.modelContainer)
    }

    /// Demo/screenshot runs use an in-memory store so seeded sample ratings
    /// never touch the user's real data; normal launches use the persistent store.
    static let modelContainer: ModelContainer = {
        if DemoMode.isActive {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: Rating.self, configurations: config)
        }
        // Cross-device iCloud sync is opt-in (Settings ▸ Sync across my devices),
        // off by default so each device keeps its own ratings and model. When on,
        // use CloudKit's automatic private-database sync; when off, keep the store
        // device-local (the app's CloudKit entitlement — used by developer sharing
        // and Compare — would otherwise make SwiftData's default .automatic sync
        // silently). The container is built once at launch, so the toggle only
        // takes effect on the next launch.
        let syncOn = UserDefaults.standard.bool(forKey: SettingsKey.syncAcrossDevices)
        let config = ModelConfiguration(cloudKitDatabase: syncOn ? .automatic : .none)
        if let container = try? ModelContainer(for: Rating.self, configurations: config) {
            return container
        }
        // If CloudKit setup fails (misconfiguration, unavailable), fall back to a
        // local store so the app still launches instead of crashing.
        let local = ModelConfiguration(cloudKitDatabase: .none)
        return try! ModelContainer(for: Rating.self, configurations: local)
    }()
}
