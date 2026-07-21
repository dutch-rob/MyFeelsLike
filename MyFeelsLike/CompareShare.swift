// SPDX-License-Identifier: GPL-3.0-or-later
//
//  CompareShare.swift
//  MyFeelsLike
//
//  Backend for the persistent "Compare with" feature. Each install has a long,
//  unguessable share ID and publishes *only its model* (regression coefficients
//  + diagnostics — no ratings, no place, no coordinates, no identity beyond a
//  chosen display name) to the app's CloudKit *public* database, keyed by that
//  share ID. To compare, one person learns another's share ID (via a nearby
//  handshake or a texted link) and fetches their model record by its exact
//  record name.
//
//  Privacy model: records are fetched by exact record name only. As long as the
//  CompareModel record type has NO queryable index (recordName included), the
//  records can't be listed or enumerated — a share ID is effectively a
//  capability. Guessing a random UUID is infeasible. See PRIVACY.md.
//
//  Requires iCloud: publishing your own model needs a signed-in iCloud account.
//  Fetching a peer surfaces a typed error so the UI can say *whose* iCloud is
//  the problem (yours, for publishing; theirs, when their record is missing).
//

import Foundation
import CloudKit
import OSLog

private let log = Logger(subsystem: "robotex.MyFeelsLike", category: "Compare")

/// A compare invite received from an opened deep link — a share ID + the
/// sender's name, plus a nonce so repeated invites from the same person still
/// register as a change to any observer.
struct CompareInvite: Equatable {
    let id: String
    let name: String
    /// One-time token from the link, used to mirror the acceptance back.
    let token: String?
    /// Embedded snapshot model (QR / texted model); nil for a live CloudKit invite.
    let model: RegressionState?
    let nonce: UUID

    // Each parse gets a fresh nonce, so that alone identifies a distinct invite
    // (avoids needing RegressionState to be Equatable).
    static func == (l: CompareInvite, r: CompareInvite) -> Bool { l.nonce == r.nonce }
}

/// A peer's shared model, reconstructed from their CloudKit record. The full
/// `RegressionState` (including invXtX) is carried, so their band shows the same
/// reliability fade it would on their own phone.
struct PeerModel {
    let shareID: String
    let name: String
    let model: RegressionState
    let updatedAt: Date?
}

/// Why a compare operation couldn't complete, phrased so the UI can name whose
/// iCloud is at fault.
enum CompareError: Error {
    /// This install has no fitted model yet — nothing to publish.
    case noModel
    /// *Your* iCloud account is unavailable, so you can't publish your model.
    case youNotSignedIn
    /// The peer's record wasn't found: they haven't shared, deleted their share,
    /// or aren't signed into iCloud on their phone.
    case peerNotFound
    /// The peer's record exists but couldn't be decoded (version skew / corrupt).
    case peerUnreadable
    /// The peer cancelled the comparison (our ID is in their revoked list).
    case endedByPeer
    /// Network or other CloudKit failure; carries a human-readable description.
    case other(String)

    var isYourAccount: Bool { if case .youNotSignedIn = self { return true } else { return false } }
}

enum CompareShare {

    static let recordType = "CompareModel"
    private static let shareIDKey = "compareShareID"
    /// Bump if the stored model JSON format changes incompatibly.
    private static let schemaVersion = 1

    private static var database: CKDatabase { CKContainer.default().publicCloudDatabase }

    // MARK: Identity

    /// This install's stable, long, unguessable share ID (a random UUID in hex,
    /// no dashes). Not derived from the Apple ID. Handed to peers so they can
    /// fetch this install's model; treated as a capability, so keep it out of
    /// logs and analytics.
    static var myShareID: String {
        let d = UserDefaults.standard
        if let s = d.string(forKey: shareIDKey), !s.isEmpty { return s }
        let s = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        d.set(s, forKey: shareIDKey)
        return s
    }

    private static func recordID(for shareID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "compare-\(shareID)")
    }

    // MARK: Revocations (mutual cancel)

    private static let revokedKey = "compareRevokedIDs"

    /// Share IDs this user has cancelled. Published in our record so that when
    /// the other person refreshes and sees their own ID here, their app knows we
    /// ended the comparison and drops us too.
    static var revokedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: revokedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: revokedKey) }
    }

    static func revoke(_ shareID: String) {
        var s = revokedIDs; s.insert(shareID.lowercased()); revokedIDs = s
    }

    /// Clear a revocation (e.g. the same person is re-added later), so they can
    /// see us again after the next publish.
    static func unrevoke(_ shareID: String) {
        var s = revokedIDs; s.remove(shareID.lowercased()); revokedIDs = s
    }

    // MARK: Invite links (texted / shared)

    static let urlScheme = "myfeelslike"
    static let urlHost   = "compare"

    /// A deep link that adds *this* install as a compare peer when opened, and
    /// carries a one-time token so the acceptance can be mirrored back to us:
    /// `myfeelslike://compare?id=<myShareID>&name=<name>&t=<token>`. The token is
    /// remembered locally so we can collect the acceptance on our next refresh.
    static func inviteURL(name: String) -> URL? {
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        sentInviteTokens = Array((sentInviteTokens + [token]).suffix(50))
        var c = URLComponents()
        c.scheme = urlScheme
        c.host   = urlHost
        var items = [URLQueryItem(name: "id", value: myShareID),
                     URLQueryItem(name: "t", value: token)]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "name", value: trimmed)) }
        c.queryItems = items
        return c.url
    }

    /// A deep link that carries this install's model *embedded* (a snapshot),
    /// for sharing via QR code or a texted/emailed link with no server:
    /// `myfeelslike://compare?m=<payload>&id=<myShareID>`. The recipient imports
    /// the model as-is (no auto-refresh). `id` keys the peer so re-scanning an
    /// updated model replaces it rather than adding a duplicate. Encoding the
    /// deep link (not just the raw payload) means any Camera-app QR scan opens
    /// the app directly — no in-app scanner needed.
    static func modelInviteURL(name: String, model: RegressionState) -> URL? {
        var c = URLComponents()
        c.scheme = urlScheme
        c.host   = urlHost
        c.queryItems = [URLQueryItem(name: "m", value: CompareModelCodec.encodedString(model, name: name)),
                        URLQueryItem(name: "id", value: myShareID)]
        return c.url
    }

    /// An opened compare deep link. `model` is set when the link embeds a
    /// snapshot (QR / texted model); otherwise it's a live CloudKit invite.
    struct ParsedInvite {
        let id: String
        let name: String
        let token: String?
        let model: RegressionState?
    }

    /// Parse an incoming compare deep link. Returns nil for anything that isn't
    /// a compare invite or lacks an id.
    static func parseInvite(_ url: URL) -> ParsedInvite? {
        guard url.scheme?.lowercased() == urlScheme,
              url.host?.lowercased() == urlHost else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let id = items.first(where: { $0.name == "id" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return nil }
        // Embedded model (snapshot) — name comes from the payload.
        var model: RegressionState?
        var embeddedName = ""
        if let payload = items.first(where: { $0.name == "m" })?.value,
           let decoded = CompareModelCodec.decodeString(payload) {
            model = decoded.model
            embeddedName = decoded.name
        }
        let name = items.first(where: { $0.name == "name" })?.value
            ?? (embeddedName.isEmpty ? "" : embeddedName)
        let token = items.first(where: { $0.name == "t" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedInvite(id: id, name: name, token: (token?.isEmpty == false) ? token : nil, model: model)
    }

    // MARK: Two-way invite (mirror the acceptance back to the inviter)

    private static let sentInvitesKey = "compareSentInvites"

    /// Tokens for invites this user has sent that are still awaiting acceptance.
    static var sentInviteTokens: [String] {
        get { UserDefaults.standard.stringArray(forKey: sentInvitesKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: sentInvitesKey) }
    }

    /// The invitee calls this after opening an invite: it writes a small record
    /// under the invite's token carrying our share ID + name, so the inviter —
    /// who knows the token — can add us back on their next refresh.
    static func acceptInvite(token: String, myName: String) async {
        guard await accountAvailable() else { return }
        let rec = CKRecord(recordType: recordType,
                           recordID: CKRecord.ID(recordName: "accept-\(token)"))
        rec["name"]   = myName.isEmpty ? "MyFeelsLike user" : myName
        rec["json"]   = myShareID           // reuse json as the accepter's id
        rec["schema"] = schemaVersion
        do {
            _ = try await database.modifyRecords(saving: [rec], deleting: [],
                                                 savePolicy: .allKeys, atomically: false)
        } catch {
            log.error("Accept-invite write failed: \(describe(error), privacy: .public)")
        }
    }

    /// The inviter calls this on refresh: for each pending sent token, look for
    /// an acceptance record; return the accepters (share ID + name), and clear
    /// the token + delete the record once collected.
    static func collectAcceptances() async -> [(id: String, name: String)] {
        var found: [(id: String, name: String)] = []
        var remaining = sentInviteTokens
        for token in sentInviteTokens {
            let rid = CKRecord.ID(recordName: "accept-\(token)")
            guard let rec = try? await database.record(for: rid),
                  let sid = (rec["json"] as? String)?.lowercased(), !sid.isEmpty else { continue }
            let name = (rec["name"] as? String) ?? "Someone"
            found.append((id: sid, name: name))
            remaining.removeAll { $0 == token }
            _ = try? await database.modifyRecords(saving: [], deleting: [rid], atomically: false)
        }
        sentInviteTokens = remaining
        return found
    }

    // MARK: Account status

    /// Whether this device can write to CloudKit (needed to publish your model).
    static func accountAvailable() async -> Bool {
        (try? await CKContainer.default().accountStatus()) == .available
    }

    // MARK: Publish (my model)

    /// Publish (or update) this install's model under `myShareID`. Stores the
    /// full `RegressionState` as JSON plus the display name and a timestamp.
    @discardableResult
    static func publish(name: String, model: RegressionState?) async -> Result<Void, CompareError> {
        guard let model else { return .failure(.noModel) }
        guard await accountAvailable() else {
            log.notice("Publish skipped: iCloud account not available.")
            return .failure(.youNotSignedIn)
        }
        guard let data = try? JSONEncoder().encode(model),
              let json = String(data: data, encoding: .utf8) else {
            return .failure(.other("Could not encode model."))
        }
        let rec = CKRecord(recordType: recordType, recordID: recordID(for: myShareID))
        rec["name"]    = name.isEmpty ? "MyFeelsLike user" : name
        rec["ts"]      = model.lastFitAt
        rec["schema"]  = schemaVersion
        rec["json"]    = json
        rec["revoked"] = revokedIDs.sorted().joined(separator: ",")
        do {
            _ = try await database.modifyRecords(saving: [rec], deleting: [],
                                                 savePolicy: .allKeys, atomically: false)
            log.notice("Published compare model (\(model.ratingCount, privacy: .public) ratings).")
            return .success(())
        } catch {
            log.error("Publish failed: \(describe(error), privacy: .public)")
            return .failure(map(error))
        }
    }

    /// Remove this install's published model (e.g. the user turns compare off).
    static func unpublish() async {
        do {
            _ = try await database.modifyRecords(saving: [], deleting: [recordID(for: myShareID)],
                                                 atomically: false)
            log.notice("Unpublished compare model.")
        } catch {
            log.error("Unpublish failed: \(describe(error), privacy: .public)")
        }
    }

    // MARK: Fetch (a peer's model)

    /// Fetch a peer's published model by their share ID.
    static func fetch(shareID: String) async -> Result<PeerModel, CompareError> {
        let cleaned = shareID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return .failure(.peerNotFound) }
        do {
            let rec = try await database.record(for: recordID(for: cleaned))
            // They cancelled the comparison if our own share ID is in their
            // revoked list — treat it as ended so we drop them too.
            let revoked = (rec["revoked"] as? String)?
                .split(separator: ",").map { String($0) } ?? []
            if revoked.contains(myShareID) { return .failure(.endedByPeer) }
            guard let json = rec["json"] as? String, let data = json.data(using: .utf8),
                  let model = try? JSONDecoder().decode(RegressionState.self, from: data) else {
                return .failure(.peerUnreadable)
            }
            let name = (rec["name"] as? String) ?? "Someone"
            return .success(PeerModel(shareID: cleaned, name: name, model: model,
                                      updatedAt: rec["ts"] as? Date))
        } catch let ck as CKError where ck.code == .unknownItem {
            return .failure(.peerNotFound)
        } catch {
            log.error("Fetch failed: \(describe(error), privacy: .public)")
            return .failure(map(error))
        }
    }

    // MARK: Errors

    /// Map a CloudKit error to the typed CompareError the UI reasons about.
    private static func map(_ error: Error) -> CompareError {
        guard let ck = error as? CKError else { return .other(error.localizedDescription) }
        switch ck.code {
        case .notAuthenticated:            return .youNotSignedIn
        case .unknownItem:                 return .peerNotFound
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
            return .other("Network unavailable. Check your connection and try again.")
        default:                           return .other(describe(ck))
        }
    }

    /// Human-readable CloudKit error including code + any partial errors.
    private static func describe(_ error: Error) -> String {
        guard let ck = error as? CKError else { return error.localizedDescription }
        var parts = ["CKError \(ck.errorCode) (\(ck.localizedDescription))"]
        for (item, e) in (ck.partialErrorsByItemID ?? [:]) {
            let code = (e as? CKError).map { "\($0.errorCode)" } ?? "?"
            parts.append("[\(item): code \(code)]")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Persistent list of people you're comparing with

/// One saved comparison link. Stored locally (not synced across your devices),
/// so a link survives quitting the app: on the next open we re-fetch the peer's
/// model from CloudKit by `shareID`.
struct ComparePeer: Codable, Identifiable, Equatable {
    let shareID: String
    var name: String
    var addedAt: Date
    /// A snapshot model imported from a QR / texted link. When set, this peer is
    /// used as-is and never fetched or refreshed from CloudKit.
    var embeddedModel: RegressionState?
    var id: String { shareID }
}

/// UserDefaults-backed store of the people you're comparing with. Deliberately
/// device-local (no CloudKit/SwiftData sync) — the list of who you compare with
/// is nobody else's business and shouldn't fan out to your other devices.
enum ComparePeerStore {
    private static let key = "comparePeers"

    static func load() -> [ComparePeer] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let peers = try? JSONDecoder().decode([ComparePeer].self, from: data) else { return [] }
        return peers.sorted { $0.addedAt < $1.addedAt }
    }

    static func save(_ peers: [ComparePeer]) {
        guard let data = try? JSONEncoder().encode(peers) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Add a peer (or update the stored name if already present). Never adds
    /// yourself. Returns the updated list.
    @discardableResult
    static func add(shareID: String, name: String, embeddedModel: RegressionState? = nil) -> [ComparePeer] {
        let cleaned = shareID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty, cleaned != CompareShare.myShareID else { return load() }
        var peers = load()
        if let i = peers.firstIndex(where: { $0.shareID == cleaned }) {
            if !name.isEmpty { peers[i].name = name }
            if let embeddedModel { peers[i].embeddedModel = embeddedModel }   // re-scan updates the snapshot
        } else {
            peers.append(ComparePeer(shareID: cleaned, name: name.isEmpty ? "Someone" : name,
                                     addedAt: Date(), embeddedModel: embeddedModel))
        }
        save(peers)
        return peers
    }

    @discardableResult
    static func remove(shareID: String) -> [ComparePeer] {
        var peers = load()
        peers.removeAll { $0.shareID == shareID }
        save(peers)
        return peers
    }

    static func removeAll() { UserDefaults.standard.removeObject(forKey: key) }
}
