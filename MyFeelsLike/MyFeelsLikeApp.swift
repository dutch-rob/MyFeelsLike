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
        return try! ModelContainer(for: Rating.self)
    }()
}
