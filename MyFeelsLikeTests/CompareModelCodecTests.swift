// SPDX-License-Identifier: GPL-3.0-or-later
//
//  CompareModelCodecTests.swift
//  MyFeelsLikeTests
//
//  The compact model codec must round-trip a model (within Float32 precision)
//  and stay small enough for a QR code even at the feature ceiling.
//

import Testing
import Foundation
@testable import MyFeelsLike

struct CompareModelCodecTests {

    /// Build a model with `p` features and a symmetric invXtX.
    private func model(features p: Int, ratingCount: Int = 42) -> RegressionState {
        let feats = Array(Feature.allCases.prefix(p))
        let m = p + 1
        var inv = Array(repeating: Array(repeating: 0.0, count: m), count: m)
        for i in 0..<m { for j in i..<m { let v = Double(i + 1) * 0.01 + Double(j) * 0.001; inv[i][j] = v; inv[j][i] = v } }
        return RegressionState(
            selectedFeatures: feats,
            coefficients: (0..<(p + 1)).map { Double($0) * 1.5 - 3 },
            means: (0..<p).map { Double($0) * 2 + 10 },
            stds:  (0..<p).map { Double($0) * 0.5 + 1 },
            rSquared: 0.9, aicc: 12.3, ratingCount: ratingCount,
            lastFitAt: Date(), invXtX: inv)
    }

    @Test func roundTripsWithinFloat32Precision() throws {
        let m = model(features: 4)
        let (back, name) = try #require(CompareModelCodec.decode(CompareModelCodec.encode(m, name: "Alex")))
        #expect(name == "Alex")
        #expect(back.selectedFeatures == m.selectedFeatures)
        #expect(back.ratingCount == m.ratingCount)
        for (a, b) in zip(back.coefficients, m.coefficients) { #expect(abs(a - b) < 1e-4) }
        for (a, b) in zip(back.means, m.means) { #expect(abs(a - b) < 1e-4) }
        for (a, b) in zip(back.stds, m.stds) { #expect(abs(a - b) < 1e-4) }
        let inv = try #require(back.invXtX)
        #expect(inv.count == m.selectedFeatures.count + 1)
        #expect(inv[1][2] == inv[2][1])   // symmetry preserved
        for i in 0..<inv.count { for j in 0..<inv.count { #expect(abs(inv[i][j] - m.invXtX![i][j]) < 1e-4) } }
    }

    @Test func base64URLRoundTrips() throws {
        let m = model(features: 6)
        let s = CompareModelCodec.encodedString(m, name: "Sam")
        #expect(!s.contains("+") && !s.contains("/") && !s.contains("="))
        let (back, name) = try #require(CompareModelCodec.decodeString(s))
        #expect(name == "Sam")
        #expect(back.selectedFeatures.count == 6)
    }

    @Test func staysWithinQRBudget() throws {
        // The size-aware encoder keeps every payload under the QR budget by
        // dropping invXtX only when a model is too big to fit with it.
        for p in [3, 6, 10, Feature.allCases.count] {
            let b64 = CompareModelCodec.encodedString(model(features: p), name: "Averagename").count
            #expect(b64 <= CompareModelCodec.qrBudget, "p=\(p): \(b64) B base64url")
        }
    }

    @Test func keepsReliabilityForNormalModelsDropsForHuge() throws {
        // A realistic model keeps its reliability matrix…
        let normal = try #require(CompareModelCodec.decode(CompareModelCodec.encode(model(features: 6), name: "A")))
        #expect(normal.model.invXtX != nil)
        // …the (unrealistic) all-features ceiling drops it to stay scannable.
        let huge = try #require(CompareModelCodec.decode(CompareModelCodec.encode(model(features: Feature.allCases.count), name: "A")))
        #expect(huge.model.invXtX == nil)
    }

    @Test func decodesGarbageAsNil() {
        #expect(CompareModelCodec.decode(Data([9, 9, 9])) == nil)   // bad version
        #expect(CompareModelCodec.decodeString("not base64 @@@") == nil)
    }
}
