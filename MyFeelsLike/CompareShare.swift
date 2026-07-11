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
    let nonce: UUID
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

    // MARK: Invite links (texted / shared)

    static let urlScheme = "myfeelslike"
    static let urlHost   = "compare"

    /// A deep link that adds *this* install as a compare peer when opened:
    /// `myfeelslike://compare?id=<myShareID>&name=<name>`.
    static func inviteURL(name: String) -> URL? {
        var c = URLComponents()
        c.scheme = urlScheme
        c.host   = urlHost
        var items = [URLQueryItem(name: "id", value: myShareID)]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "name", value: trimmed)) }
        c.queryItems = items
        return c.url
    }

    /// Parse an incoming compare deep link into (share ID, sender name).
    /// Returns nil for anything that isn't a compare invite or lacks an id.
    static func parseInvite(_ url: URL) -> (id: String, name: String)? {
        guard url.scheme?.lowercased() == urlScheme,
              url.host?.lowercased() == urlHost else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let id = items.first(where: { $0.name == "id" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return nil }
        let name = items.first(where: { $0.name == "name" })?.value ?? ""
        return (id, name)
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
        rec["name"]   = name.isEmpty ? "MyFeelsLike user" : name
        rec["ts"]     = model.lastFitAt
        rec["schema"] = schemaVersion
        rec["json"]   = json
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
    static func add(shareID: String, name: String) -> [ComparePeer] {
        let cleaned = shareID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty, cleaned != CompareShare.myShareID else { return load() }
        var peers = load()
        if let i = peers.firstIndex(where: { $0.shareID == cleaned }) {
            if !name.isEmpty { peers[i].name = name }
        } else {
            peers.append(ComparePeer(shareID: cleaned, name: name.isEmpty ? "Someone" : name,
                                     addedAt: Date()))
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
