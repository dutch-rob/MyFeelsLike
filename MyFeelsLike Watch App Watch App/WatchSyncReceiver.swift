// SPDX-License-Identifier: GPL-3.0-or-later
//
//  WatchSyncReceiver.swift
//  MyFeelsLike Watch App
//
//  Receives the model + settings the phone pushes via WatchConnectivity,
//  caches the latest in the App Group so it survives launches, and publishes
//  it to the watch UI. `version` bumps on every update so views can re-apply
//  the model without a full weather refetch.
//

import Foundation
import WatchConnectivity
import Combine

final class WatchSyncReceiver: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSyncReceiver()

    @Published private(set) var payload: WatchSyncPayload?
    @Published private(set) var version: Int = 0

    private let store = UserDefaults(suiteName: "group.robotex.MyFeelsLike")
    private let key = "watchSyncPayload"

    private override init() {
        super.init()
        if DemoMode.isActive {
            payload = DemoWatchPayload.payload
            return
        }
        if let data = store?.data(forKey: key),
           let p = try? JSONDecoder().decode(WatchSyncPayload.self, from: data) {
            payload = p
        }
    }

    func start() {
        // Screenshot mode is self-contained: don't let a real phone (or a
        // stale cached context) replace the embedded demo model.
        guard !DemoMode.isActive else { return }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        if !session.receivedApplicationContext.isEmpty {
            apply(session.receivedApplicationContext)
        }
    }

    private func apply(_ context: [String: Any]) {
        guard let p = WatchSyncPayload.from(applicationContext: context) else { return }
        if let data = try? JSONEncoder().encode(p) { store?.set(data, forKey: key) }
        mirrorSettings(p)
        DispatchQueue.main.async {
            self.payload = p
            self.version &+= 1
        }
    }

    /// Copy the synced presentation settings into this watch's own defaults.
    /// ColorScale and the date formatters read them from there, so a setting
    /// changed on the phone has to land in the same place on the watch —
    /// otherwise the watch keeps drawing full color while the phone does not.
    private func mirrorSettings(_ p: WatchSyncPayload) {
        let d = UserDefaults.standard
        if let mode = p.colorVisionMode { d.set(mode, forKey: "colorVisionMode") }
        if let clock = p.use12HourClock { d.set(clock, forKey: "use12HourClock") }
        if let style = p.sunShadeStyle { d.set(style, forKey: "sunShadeStyle") }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        apply(userInfo)
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if !session.receivedApplicationContext.isEmpty {
            apply(session.receivedApplicationContext)
        }
    }
}
