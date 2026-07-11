// SPDX-License-Identifier: GPL-3.0-or-later
//
//  CompareCoordinator.swift
//  MyFeelsLike
//
//  Drives the persistent side of the Compare screen: publishes this install's
//  model, loads the saved list of people you compare with, and fetches each of
//  their models from CloudKit (with a per-peer loading/failed state so the UI
//  can show progress and name whose iCloud is missing). See CompareShare.swift
//  for the network + storage layer.
//

import Foundation
import Combine

/// A saved peer plus the current state of loading their model from CloudKit.
struct LoadedPeer: Identifiable {
    let peer: ComparePeer
    var state: State
    var id: String { peer.shareID }

    enum State {
        case loading
        case loaded(RegressionState)
        case failed(CompareError)
    }
}

@MainActor
final class CompareCoordinator: ObservableObject {
    /// Saved peers with their load state, oldest first.
    @Published private(set) var loaded: [LoadedPeer] = []
    /// nil until first checked; false means your own iCloud can't publish.
    @Published private(set) var accountAvailable: Bool? = nil
    /// Set when publishing your own model failed (e.g. not signed in).
    @Published private(set) var publishFailed = false
    /// True while a refresh is in flight (drives the spinner on the button).
    @Published private(set) var isRefreshing = false

    /// One-shot guard so we withdraw the published model only once after the
    /// user turns sharing off (reset whenever sharing is on again).
    private var didUnpublish = false

    /// Whether the user lets others compare with them (publishes your model).
    /// Defaults to true when the preference has never been set.
    private var shareEnabled: Bool {
        let d = UserDefaults.standard
        return d.object(forKey: SettingsKey.shareForCompare) == nil
            ? true : d.bool(forKey: SettingsKey.shareForCompare)
    }

    /// First appearance: show saved peers immediately as "loading", then publish
    /// our model and fetch everyone.
    /// Our identity, cached from the latest start/refresh so `remove` can
    /// republish our revocation list without the caller passing it again.
    private var lastMyName = ""
    private var lastMyModel: RegressionState?

    func start(myName: String, myModel: RegressionState?) {
        loaded = ComparePeerStore.load().map { LoadedPeer(peer: $0, state: .loading) }
        Task { await refresh(myName: myName, myModel: myModel) }
    }

    /// Publish our model (if signed in) and re-fetch every saved peer.
    func refresh(myName: String, myModel: RegressionState?) async {
        lastMyName = myName
        lastMyModel = myModel
        isRefreshing = true
        defer { isRefreshing = false }

        let available = await CompareShare.accountAvailable()
        accountAvailable = available
        if !shareEnabled {
            // Sharing turned off: withdraw our model once, keep reading others'.
            if !didUnpublish { await CompareShare.unpublish(); didUnpublish = true }
            publishFailed = false
        } else if available, myModel != nil {
            didUnpublish = false
            let result = await CompareShare.publish(name: myName, model: myModel)
            publishFailed = { if case .failure = result { return true } else { return false } }()
        } else {
            didUnpublish = false
            publishFailed = false   // no model, or not signed in (surfaced separately)
        }

        // Collect any acceptances of invites we sent, so people we texted appear
        // on our side too (two-way inclusion).
        for a in await CompareShare.collectAcceptances() {
            CompareShare.unrevoke(a.id)
            ComparePeerStore.add(shareID: a.id, name: a.name)
        }

        // Reconcile the shown list with what's saved (peers may have been added
        // since start), keeping any state we already have so rows don't flicker.
        let saved = ComparePeerStore.load()
        loaded = saved.map { p in
            LoadedPeer(peer: p,
                       state: loaded.first { $0.peer.shareID == p.shareID }?.state ?? .loading)
        }

        for p in saved {
            let result = await CompareShare.fetch(shareID: p.shareID)
            guard let i = loaded.firstIndex(where: { $0.peer.shareID == p.shareID }) else { continue }
            switch result {
            case .success(let pm):
                // Keep the display name fresh from the peer's own record.
                if !pm.name.isEmpty, pm.name != loaded[i].peer.name {
                    ComparePeerStore.add(shareID: p.shareID, name: pm.name)
                    loaded[i] = LoadedPeer(
                        peer: ComparePeer(shareID: p.shareID, name: pm.name, addedAt: p.addedAt),
                        state: .loaded(pm.model))
                } else {
                    loaded[i].state = .loaded(pm.model)
                }
            case .failure(.endedByPeer):
                // They cancelled the comparison — drop them on our side too.
                ComparePeerStore.remove(shareID: p.shareID)
                loaded.removeAll { $0.peer.shareID == p.shareID }
            case .failure(let e):
                loaded[i].state = .failed(e)
            }
        }
    }

    /// Add (or update) a peer, then refresh so their band appears. Re-adding
    /// someone previously cancelled clears our revocation so they can see us again.
    /// When `token` is set (opened from a texted invite), also mirror the
    /// acceptance back so the inviter adds us too.
    func add(shareID: String, name: String, token: String? = nil,
             myName: String, myModel: RegressionState?) {
        CompareShare.unrevoke(shareID)
        ComparePeerStore.add(shareID: shareID, name: name)
        Task {
            if let token { await CompareShare.acceptInvite(token: token, myName: myName) }
            await refresh(myName: myName, myModel: myModel)
        }
    }

    /// Cancel a comparison: forget them locally *and* record the revocation in
    /// our published model, so their app drops us on its next refresh.
    func remove(_ peer: ComparePeer) {
        CompareShare.revoke(peer.shareID)
        ComparePeerStore.remove(shareID: peer.shareID)
        loaded.removeAll { $0.peer.shareID == peer.shareID }
        // Republish so the revocation reaches CloudKit right away.
        Task { await refresh(myName: lastMyName, myModel: lastMyModel) }
    }
}
