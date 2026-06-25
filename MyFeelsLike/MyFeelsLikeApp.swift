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
        if UserDefaults.standard.object(forKey: "useFahrenheit") == nil {
            let region = Locale.current.region?.identifier ?? ""
            UserDefaults.standard.set(fahrenheitRegions.contains(region), forKey: "useFahrenheit")
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
