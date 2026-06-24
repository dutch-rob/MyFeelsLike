//
//  ContentView.swift
//  MyFeelsLike Watch App
//
//  Root screen: horizontal page tabs Toda+y → 10-day → Table. The Today page
//  scrolls vertically to reveal the wind/precip graph. Fetches on appear /
//  foreground; re-applies the model (no refetch) when a fresh sync arrives.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var model = WatchWeatherModel()
    @ObservedObject private var sync = WatchSyncReceiver.shared
    @Environment(\.scenePhase) private var scenePhase

    // 5-tab layout for circular (wrap-around) swiping, like the phone:
    //   0 = Table phantom  → real tab is 3
    //   1 = Today (real, default)
    //   2 = 10-day (real)
    //   3 = Table (real)
    //   4 = Today phantom  → real tab is 1
    @State private var selectedTab = 1

    var body: some View {
        TabView(selection: $selectedTab) {
            WatchTableView(model: model).tag(0)
            WatchTodayView(model: model).tag(1)
            WatchTenDayView(model: model).tag(2)
            WatchTableView(model: model).tag(3)
            WatchTodayView(model: model).tag(4)
        }
        .tabViewStyle(.page)
        .onChange(of: selectedTab) { _, tab in
            guard tab == 0 || tab == 4 else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { selectedTab = tab == 0 ? 3 : 1 }
        }
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
