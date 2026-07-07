//
//  NearbyCompare.swift
//  MyFeelsLike
//
//  Phase 2 of Compare: live "nearby" links over MultipeerConnectivity. Two
//  phones discover each other, one invites, the other accepts for 1 hour or
//  until one of them cancels. On connect they exchange their regression models
//  (and re-send whenever a model changes), so each can show the other's
//  MyFeelsLike colours applied to its own local forecast.
//
//  One MCSession per peer, so every link has an independent lifetime and can be
//  ended on its own. All mutable state is touched on the main queue only.
//

import Foundation
import MultipeerConnectivity
import Combine
import UIKit

/// Message exchanged over a link. The peer's *name* travels for free in its
/// MCPeerID, so only the model + (optional) agreed deadline need sending.
private struct CompareMessage: Codable {
    enum Kind: String, Codable { case hello, modelUpdate, bye }
    var kind: Kind
    var model: RegressionState?
    var deadline: Date?     // set by the accepting side in its `hello`
}

final class NearbyCompareManager: NSObject, ObservableObject {

    static let serviceType = "mfl-compare"      // ≤15 chars, matches Info.plist Bonjour
    static let maxPeers = 6

    enum Lifetime { case oneHour, untilCancel }

    struct Discovered: Identifiable {
        let peerID: MCPeerID
        var id: String { peerID.displayName }
        var name: String { peerID.displayName }
    }

    struct Invite: Identifiable {
        let id = UUID()
        let peerID: MCPeerID
        let handler: (Bool, MCSession?) -> Void
        var name: String { peerID.displayName }
    }

    struct Peer: Identifiable {
        let peerID: MCPeerID
        var id: String { peerID.displayName }
        var name: String { peerID.displayName }
        var model: RegressionState?
        var deadline: Date?     // nil ⇒ until one of us cancels
    }

    // MARK: Published UI state
    @Published var isDiscovering = false
    @Published var discovered: [Discovered] = []
    @Published private(set) var pendingInvite: Invite?     // shown one at a time
    @Published private(set) var peers: [Peer] = []

    /// The phone user's current model, shared with peers. Set by the owner.
    var localModel: RegressionState?

    // MARK: MultipeerConnectivity
    private let myPeerID: MCPeerID
    private lazy var advertiser = MCNearbyServiceAdvertiser(
        peer: myPeerID, discoveryInfo: nil, serviceType: Self.serviceType)
    private lazy var browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
    private var sessions: [MCPeerID: MCSession] = [:]
    /// Deadline the local user picked when *accepting* a given peer's invite.
    private var acceptedDeadline: [MCPeerID: Date] = [:]
    private var pruneTimer: Timer?

    override init() {
        let raw = UIDevice.current.name
        let name = raw.isEmpty ? "MyFeelsLike user" : String(raw.prefix(63))
        self.myPeerID = MCPeerID(displayName: name)
        super.init()
        advertiser.delegate = self
        browser.delegate = self
    }

    var atCapacity: Bool { peers.count >= Self.maxPeers }

    // MARK: Discovery

    func startDiscovery() {
        guard !isDiscovering else { return }
        isDiscovering = true
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        ensurePruneTimer()
    }

    func stopDiscovery() {
        guard isDiscovering else { return }
        isDiscovering = false
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        discovered.removeAll()
    }

    /// Invite a discovered peer. The *accepter* chooses the link's lifetime.
    func invite(_ d: Discovered) {
        guard !atCapacity, sessions[d.peerID] == nil else { return }
        let session = makeSession(for: d.peerID)
        browser.invitePeer(d.peerID, to: session, withContext: nil, timeout: 30)
    }

    // MARK: Accept / decline an incoming invite

    func accept(_ invite: Invite, lifetime: Lifetime) {
        guard !atCapacity else { decline(invite); return }
        let session = makeSession(for: invite.peerID)
        if lifetime == .oneHour {
            acceptedDeadline[invite.peerID] = Date().addingTimeInterval(3600)
        }
        invite.handler(true, session)
        if pendingInvite?.id == invite.id { pendingInvite = nil }
    }

    func decline(_ invite: Invite) {
        invite.handler(false, nil)
        if pendingInvite?.id == invite.id { pendingInvite = nil }
    }

    // MARK: Local model changes → tell every peer

    func updateLocalModel(_ model: RegressionState?) {
        localModel = model
        broadcast(CompareMessage(kind: .modelUpdate, model: model, deadline: nil))
    }

    // MARK: Ending links

    func cancel(_ peer: Peer) { disconnect(peer.peerID, sendBye: true) }

    func cancelAll() {
        for id in Array(sessions.keys) { disconnect(id, sendBye: true) }
        stopDiscovery()
    }

    // MARK: - Internals (main queue only)

    private func makeSession(for peerID: MCPeerID) -> MCSession {
        let s = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        sessions[peerID] = s
        return s
    }

    private func disconnect(_ peerID: MCPeerID, sendBye: Bool) {
        if let s = sessions[peerID] {
            if sendBye { send(CompareMessage(kind: .bye, model: nil, deadline: nil), over: s) }
            s.disconnect()
        }
        sessions[peerID] = nil
        acceptedDeadline[peerID] = nil
        peers.removeAll { $0.peerID == peerID }
        discovered.removeAll { $0.peerID == peerID }
    }

    private func broadcast(_ msg: CompareMessage) {
        for s in sessions.values { send(msg, over: s) }
    }

    private func send(_ msg: CompareMessage, over session: MCSession) {
        guard !session.connectedPeers.isEmpty, let data = try? JSONEncoder().encode(msg) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    private func ensurePruneTimer() {
        guard pruneTimer == nil else { return }
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.pruneExpired()
        }
    }

    private func pruneExpired() {
        let now = Date()
        for p in peers where (p.deadline.map { now >= $0 } ?? false) {
            disconnect(p.peerID, sendBye: true)
        }
        if sessions.isEmpty && !isDiscovering {
            pruneTimer?.invalidate(); pruneTimer = nil
        }
    }

    /// Handle an incoming message (already hopped to main).
    private func handle(_ msg: CompareMessage, from peerID: MCPeerID) {
        switch msg.kind {
        case .bye:
            disconnect(peerID, sendBye: false)
        case .hello, .modelUpdate:
            guard let idx = peers.firstIndex(where: { $0.peerID == peerID }) else { return }
            peers[idx].model = msg.model
            if let d = msg.deadline { peers[idx].deadline = d }   // accepter's deadline wins
        }
    }

    /// A session reached `.connected` for `peerID` (already on main).
    private func onConnected(_ peerID: MCPeerID, session: MCSession) {
        discovered.removeAll { $0.peerID == peerID }
        if !peers.contains(where: { $0.peerID == peerID }) {
            guard !atCapacity else { disconnect(peerID, sendBye: false); return }
            peers.append(Peer(peerID: peerID, model: nil, deadline: acceptedDeadline[peerID]))
        }
        // Say hello with my model; include my chosen deadline if I accepted.
        send(CompareMessage(kind: .hello, model: localModel, deadline: acceptedDeadline[peerID]),
             over: session)
        ensurePruneTimer()
    }
}

// MARK: - Browser (finding peers to invite)

extension NearbyCompareManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String : String]?) {
        DispatchQueue.main.async {
            guard peerID != self.myPeerID,
                  self.sessions[peerID] == nil,
                  !self.discovered.contains(where: { $0.peerID == peerID }) else { return }
            self.discovered.append(Discovered(peerID: peerID))
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { self.discovered.removeAll { $0.peerID == peerID } }
    }
}

// MARK: - Advertiser (receiving invitations)

extension NearbyCompareManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            // One invite at a time, respect the peer cap, ignore duplicates.
            guard self.pendingInvite == nil, !self.atCapacity, self.sessions[peerID] == nil else {
                invitationHandler(false, nil); return
            }
            self.pendingInvite = Invite(peerID: peerID, handler: invitationHandler)
        }
    }
}

// MARK: - Session (the live link)

extension NearbyCompareManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:    self.onConnected(peerID, session: session)
            case .notConnected: self.disconnect(peerID, sendBye: false)
            case .connecting:   break
            @unknown default:   break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let msg = try? JSONDecoder().decode(CompareMessage.self, from: data) else { return }
        DispatchQueue.main.async { self.handle(msg, from: peerID) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
