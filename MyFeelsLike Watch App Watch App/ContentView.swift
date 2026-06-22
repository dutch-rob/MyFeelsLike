//
//  ContentView.swift
//  MyFeelsLike Watch App
//
//  Root screen: horizontal page tabs Today → 10-day → Table. The Today page
//  scrolls vertically to reveal the wind/precip graph. Fetches on appear /
//  foreground; re-applies the model (no refetch) when a fresh sync arrives.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var model = WatchWeatherModel()
    @ObservedObject private var sync = WatchSyncReceiver.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            WatchTodayView(model: model)
            WatchTenDayView(model: model)
            WatchTableView(model: model)
        }
        .tabViewStyle(.page)
        .onAppear {
            sync.start()
            model.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh() }
        }
        .onChange(of: sync.version) { _, _ in
            model.applyModel()
        }
    }
}

#Preview {
    ContentView()
}
