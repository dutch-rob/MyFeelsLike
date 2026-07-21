// SPDX-License-Identifier: GPL-3.0-or-later
//
//  CompareModelCodec.swift
//  MyFeelsLike
//
//  Compact, self-contained encoding of a shared model so it can travel *inside*
//  a QR code or a texted/emailed link — no server, no auto-refresh (it's a
//  snapshot of the sender's model at that moment). Cross-platform-friendly: a
//  plain little-endian binary blob, base64url-wrapped for URLs/text.
//
//  Size tricks (a QR wants well under ~1–2 KB):
//   • Float32 instead of Float64 (~7 digits is plenty for coefficients and the
//     reliability matrix, and halves every number vs binary Float64 — far less
//     than JSON text).
//   • invXtX is the inverse of a symmetric matrix, so only its upper triangle is
//     stored ((m·(m+1))/2 values instead of m²).
//   • Features are stored as their `Feature.allCases` index (one byte), not names.
//
//  Layout (little-endian):
//    u8  version
//    u8  flags            (bit 0 = invXtX present)
//    u16 ratingCount
//    u8  nameLen; name    (UTF-8)
//    u8  p                (feature count)
//    u8×p feature indices (into Feature.allCases)
//    f32×(p+1) coefficients
//    f32×p     means
//    f32×p     stds
//    f32×(m(m+1)/2) invXtX upper triangle, m = p+1   (only if flag set)
//
//  NB: feature indices rely on Feature.allCases order staying stable — only ever
//  append new cases. The version byte guards against incompatible changes.
//

import Foundation

enum CompareModelCodec {
    static let version: UInt8 = 1

    /// base64url budget for a comfortably-scannable QR (a phone-to-phone scan
    /// gets unreliable past this). If a model's reliability matrix would push it
    /// over, we drop invXtX — a model that big has plenty of ratings, so its
    /// predictions are well-covered and the reliability fade matters least.
    static let qrBudget = 1200

    // MARK: Encode

    /// Size-aware: include invXtX when it fits the QR budget, otherwise drop it.
    static func encode(_ m: RegressionState, name: String) -> Data {
        let full = encode(m, name: name, includeInvXtX: true)
        return base64urlLength(full) <= qrBudget ? full : encode(m, name: name, includeInvXtX: false)
    }

    static func encode(_ m: RegressionState, name: String, includeInvXtX: Bool) -> Data {
        var data = Data()
        func u8(_ v: Int)  { data.append(UInt8(truncatingIfNeeded: v)) }
        func u16(_ v: Int) { let x = UInt16(clamping: v).littleEndian; withUnsafeBytes(of: x) { data.append(contentsOf: $0) } }
        func f32(_ v: Double) { let bits = Float(v).bitPattern.littleEndian; withUnsafeBytes(of: bits) { data.append(contentsOf: $0) } }

        let p = m.selectedFeatures.count
        let hasInv = includeInvXtX && (m.invXtX?.count == p + 1)

        u8(Int(version))
        u8(hasInv ? 1 : 0)
        u16(m.ratingCount)
        let nameBytes = Array(name.prefix(48).utf8)
        u8(nameBytes.count)
        data.append(contentsOf: nameBytes)
        u8(p)
        for f in m.selectedFeatures { u8(Feature.allCases.firstIndex(of: f) ?? 0) }
        for c in m.coefficients { f32(c) }   // p + 1
        for v in m.means        { f32(v) }   // p
        for v in m.stds         { f32(v) }   // p
        if hasInv, let inv = m.invXtX {
            let mm = p + 1
            for i in 0..<mm { for j in i..<mm { f32(inv[i][j]) } }
        }
        return data
    }

    // MARK: Decode

    static func decode(_ data: Data) -> (model: RegressionState, name: String)? {
        let bytes = [UInt8](data)
        var o = 0
        func u8()  -> Int? { guard o < bytes.count else { return nil }; defer { o += 1 }; return Int(bytes[o]) }
        func u16() -> Int? { guard o + 2 <= bytes.count else { return nil }; let v = Int(bytes[o]) | (Int(bytes[o + 1]) << 8); o += 2; return v }
        func f32() -> Double? {
            guard o + 4 <= bytes.count else { return nil }
            let bits = UInt32(bytes[o]) | (UInt32(bytes[o+1]) << 8) | (UInt32(bytes[o+2]) << 16) | (UInt32(bytes[o+3]) << 24)
            o += 4
            let f = Float(bitPattern: bits)
            return f.isFinite ? Double(f) : 0
        }
        func floats(_ n: Int) -> [Double]? {
            var a = [Double](); a.reserveCapacity(n)
            for _ in 0..<n { guard let v = f32() else { return nil }; a.append(v) }
            return a
        }

        guard let ver = u8(), ver == Int(version), let flags = u8(), let rc = u16(),
              let nameLen = u8(), o + nameLen <= bytes.count else { return nil }
        let name = String(bytes: bytes[o..<o + nameLen], encoding: .utf8) ?? ""
        o += nameLen
        guard let p = u8() else { return nil }

        var features: [Feature] = []
        for _ in 0..<p {
            guard let idx = u8(), idx < Feature.allCases.count else { return nil }
            features.append(Feature.allCases[idx])
        }
        guard let coefficients = floats(p + 1), let means = floats(p), let stds = floats(p) else { return nil }

        var invXtX: [[Double]]? = nil
        if flags & 1 == 1 {
            let mm = p + 1
            var mat = Array(repeating: Array(repeating: 0.0, count: mm), count: mm)
            for i in 0..<mm {
                for j in i..<mm {
                    guard let v = f32() else { return nil }
                    mat[i][j] = v; mat[j][i] = v
                }
            }
            invXtX = mat
        }

        let model = RegressionState(
            selectedFeatures: features, coefficients: coefficients, means: means, stds: stds,
            rSquared: 0, aicc: 0, ratingCount: rc, lastFitAt: Date(), invXtX: invXtX)
        return (model, name)
    }

    // MARK: base64url for URLs / text / QR payload

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    private static func base64urlLength(_ data: Data) -> Int { base64url(data).count }

    static func encodedString(_ m: RegressionState, name: String) -> String {
        base64url(encode(m, name: name))
    }

    static func decodeString(_ s: String) -> (model: RegressionState, name: String)? {
        var b64 = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return decode(data)
    }
}
