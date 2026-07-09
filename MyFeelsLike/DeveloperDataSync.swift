//
//  DeveloperDataSync.swift
//  MyFeelsLike
//
//  Opt-in upload of anonymised ratings + model coefficients to the app's
//  CloudKit *public* database, so the developer can study how the app is used.
//  Off by default; controlled by the "Share data with developers" toggle.
//
//  Anonymised: records carry only a random per-install ID — never the iCloud
//  account, name, place names, or coordinates. With the record types' security
//  roles set so only the creator can read (see the setup notes), each user can
//  read only their own rows, while the developer reads everything in the
//  CloudKit Console. Turning the toggle off deletes everything this install
//  uploaded.
//

import Foundation
import CloudKit
import OSLog

private let log = Logger(subsystem: "robotex.MyFeelsLike", category: "DataSync")

enum DeveloperDataSync {

    static let consentKey = SettingsKey.shareDataWithDevs
    private static let installIDKey = "developerShareInstallID"
    private static let uploadedKey  = "developerShareUploadedRatingIDs"

    private static var database: CKDatabase { CKContainer.default().publicCloudDatabase }

    /// Stable, anonymous per-install identifier — a random UUID, not tied to the
    /// Apple ID. Lets the developer group one user's rows without identifying them.
    static var installID: String {
        let d = UserDefaults.standard
        if let s = d.string(forKey: installIDKey) { return s }
        let s = UUID().uuidString
        d.set(s, forKey: installIDKey)
        return s
    }

    /// Upload new ratings + the current model when consent is on; delete
    /// everything we previously uploaded when consent is off.
    static func sync(consent: Bool, ratings: [Rating], model: RegressionState?) {
        if consent {
            let snapshot = ratings.map { RatingLite($0) }   // detach from SwiftData before the Task
            Task { await upload(ratings: snapshot, model: model) }
        } else {
            Task { await withdraw() }
        }
    }

    // MARK: Upload

    private static func upload(ratings: [RatingLite], model: RegressionState?) async {
        let id = installID
        var uploaded = Set(UserDefaults.standard.stringArray(forKey: uploadedKey) ?? [])

        let pending = ratings.filter { !uploaded.contains($0.id) }
        var records: [CKRecord] = pending.map { $0.record(install: id) }
        if let model { records.append(modelRecord(model, install: id)) }
        guard !records.isEmpty else {
            log.notice("Nothing to upload: \(ratings.count, privacy: .public) ratings, all already sent; model \(model == nil ? "absent" : "present", privacy: .public).")
            return
        }
        await logAccountStatus()

        do {
            // atomically:false does NOT throw on per-record failures — inspect
            // each result so we only mark the records that actually saved and
            // surface any that didn't (schema/permission/auth issues).
            let result = try await database.modifyRecords(saving: records, deleting: [],
                                                          savePolicy: .allKeys, atomically: false)
            var saved = 0, failed = 0
            for (recordID, res) in result.saveResults {
                switch res {
                case .success:
                    saved += 1
                    if let ratingID = ratingID(fromRecordName: recordID.recordName, install: id) {
                        uploaded.insert(ratingID)
                    }
                case .failure(let error):
                    failed += 1
                    log.error("Save failed \(recordID.recordName, privacy: .public): \(describe(error), privacy: .public)")
                }
            }
            UserDefaults.standard.set(Array(uploaded), forKey: uploadedKey)
            log.notice("Upload finished: \(saved, privacy: .public) saved, \(failed, privacy: .public) failed.")
        } catch {
            // Operation-level failure (network, account) — pending stays pending.
            log.error("Upload failed: \(describe(error), privacy: .public)")
        }
    }

    /// Map a saved record name ("rating-<install>-<uuid>") back to the rating id,
    /// or nil for the model record (which isn't delta-tracked).
    private static func ratingID(fromRecordName name: String, install: String) -> String? {
        let prefix = "rating-\(install)-"
        return name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : nil
    }

    /// Log the CloudKit account status so a "not signed into iCloud" problem is
    /// obvious in the console rather than a silent no-op.
    private static func logAccountStatus() async {
        // Which container/DB the records actually go to (debug-level so it's
        // not chatty in production; shows in the console when needed).
        log.debug("Writing to container: \(CKContainer.default().containerIdentifier ?? "nil", privacy: .public), public database.")
        do {
            let status = try await CKContainer.default().accountStatus()
            let name: String
            switch status {
            case .available:        name = "available"
            case .noAccount:        name = "noAccount (not signed into iCloud)"
            case .restricted:       name = "restricted"
            case .couldNotDetermine: name = "couldNotDetermine"
            case .temporarilyUnavailable: name = "temporarilyUnavailable"
            @unknown default:       name = "unknown(\(status.rawValue))"
            }
            log.notice("iCloud account status: \(name, privacy: .public)")
        } catch {
            log.error("Account status check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Withdraw (consent turned off)

    private static func withdraw() async {
        let id = installID
        let uploaded = UserDefaults.standard.stringArray(forKey: uploadedKey) ?? []
        var ids = uploaded.map { CKRecord.ID(recordName: "rating-\(id)-\($0)") }
        ids.append(CKRecord.ID(recordName: "model-\(id)"))
        guard !ids.isEmpty else { return }
        do {
            _ = try await database.modifyRecords(saving: [], deleting: ids, atomically: false)
            UserDefaults.standard.removeObject(forKey: uploadedKey)
        } catch {
            log.error("Withdraw failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Model record

    private static func modelRecord(_ m: RegressionState, install: String) -> CKRecord {
        let rec = CKRecord(recordType: "SharedModel",
                           recordID: CKRecord.ID(recordName: "model-\(install)"))
        let features = m.selectedFeatures.map { $0.rawValue }
        rec["install"]     = install
        rec["ts"]          = m.lastFitAt
        rec["rSquared"]    = m.rSquared.isFinite ? m.rSquared : 0
        rec["ratingCount"] = m.ratingCount
        // Comma-joined scalar String, not a CloudKit list — lists complicate
        // the schema and can't be indexed like scalars in the Console.
        rec["features"]    = features.joined(separator: ",")
        // Compact, finite-sanitised model summary (no invXtX/aicc, which are
        // large or can be non-finite and would make the record unencodable).
        let lean = SharedModelJSON(features: features,
                                   coefficients: sanitize(m.coefficients),
                                   means: sanitize(m.means),
                                   stds: sanitize(m.stds),
                                   rSquared: m.rSquared.isFinite ? m.rSquared : 0,
                                   ratingCount: m.ratingCount)
        if let data = try? JSONEncoder().encode(lean), let s = String(data: data, encoding: .utf8) {
            rec["json"] = s
        }
        return rec
    }

    private static func sanitize(_ a: [Double]) -> [Double] { a.map { $0.isFinite ? $0 : 0 } }

    /// Human-readable CloudKit error, including the CKError code and any
    /// per-item partial errors, so failures aren't just "CAS failed".
    private static func describe(_ error: Error) -> String {
        guard let ck = error as? CKError else { return error.localizedDescription }
        var parts = ["CKError \(ck.errorCode) (\(ck.localizedDescription))"]
        for (item, e) in (ck.partialErrorsByItemID ?? [:]) {
            let code = (e as? CKError).map { "\($0.errorCode)" } ?? "?"
            parts.append("[\(item): code \(code) \(e.localizedDescription)]")
        }
        return parts.joined(separator: " ")
    }
}

/// Compact, finite model summary uploaded as the SharedModel `json` field.
private struct SharedModelJSON: Codable {
    let features: [String]
    let coefficients: [Double]
    let means: [Double]
    let stds: [Double]
    let rSquared: Double
    let ratingCount: Int
}

/// A value-type copy of the fields we upload — taken on the main actor so the
/// CloudKit work can run off the SwiftData model objects safely.
private struct RatingLite {
    let id: String
    let timestamp: Date
    let score: Double
    let activity, dress, sun: Int
    let tempC, apparentC, wetBulbC, dewC, humidity, pressurePa, windKPH: Double
    let precipProb, precipMM, cloud, cloudLow, cloudMed, cloudHigh, uv: Double
    let daylight: Bool

    init(_ r: Rating) {
        id = r.id.uuidString
        timestamp = r.timestamp
        score = r.feelsLikeScore
        activity = r.activity; dress = r.dress; sun = r.sun
        tempC = r.temperatureC; apparentC = r.apparentTemperatureC
        wetBulbC = r.wetBulbC; dewC = r.dewPointC; humidity = r.humidity
        pressurePa = r.stationPressurePa; windKPH = r.windSpeedKPH
        precipProb = r.precipProbability; precipMM = r.precipitationMM
        cloud = r.cloudCover; cloudLow = r.cloudCoverLow
        cloudMed = r.cloudCoverMedium; cloudHigh = r.cloudCoverHigh
        uv = r.uvIndex; daylight = r.isDaylight
    }

    /// Anonymised CloudKit record — no place, no coordinates, no identity.
    func record(install: String) -> CKRecord {
        let rec = CKRecord(recordType: "SharedRating",
                           recordID: CKRecord.ID(recordName: "rating-\(install)-\(id)"))
        rec["install"]    = install
        rec["ts"]         = timestamp
        rec["score"]      = score
        rec["activity"]   = activity
        rec["dress"]      = dress
        rec["sun"]        = sun
        rec["tempC"]      = tempC
        rec["apparentC"]  = apparentC
        rec["wetBulbC"]   = wetBulbC
        rec["dewC"]       = dewC
        rec["humidity"]   = humidity
        rec["pressurePa"] = pressurePa
        rec["windKPH"]    = windKPH
        rec["precipProb"] = precipProb
        rec["precipMM"]   = precipMM
        rec["cloud"]      = cloud
        rec["cloudLow"]   = cloudLow
        rec["cloudMed"]   = cloudMed
        rec["cloudHigh"]  = cloudHigh
        rec["uv"]         = uv
        rec["daylight"]   = daylight ? 1 : 0
        return rec
    }
}
