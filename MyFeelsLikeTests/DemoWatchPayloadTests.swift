// SPDX-License-Identifier: GPL-3.0-or-later
//
//  DemoWatchPayloadTests.swift
//  MyFeelsLikeTests
//
//  The watch has no ratings store and no regression code, so screenshot mode
//  there reads a pre-encoded copy of the phone's demo model
//  (DemoWatchPayload). That copy is only correct while the model-selection
//  rules that produced it still produce it — these tests fail loudly when the
//  rules change, and print a fresh payload to paste in.
//

import XCTest
@testable import MyFeelsLike

final class DemoWatchPayloadTests: XCTestCase {

    /// Prints a fresh payload for DemoWatchPayload.json. Not a test of
    /// anything — run it (and copy the output) after a rules change.
    func testPrintFreshPayload() throws {
        let payload = try XCTUnwrap(freshDemoPayload(), "demo ratings no longer fit a model")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        // xcodebuild swallows stdout from the test runner, so write it where
        // the host can fetch it: `simctl get_app_container <udid> <bundle> data`.
        let out = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DemoWatchPayload.json")
        try data.write(to: out)
        print("wrote \(out.path)")
    }

    /// The embedded copy still matches what the current rules fit.
    func testEmbeddedPayloadMatchesAFreshFit() throws {
        let fresh = try XCTUnwrap(freshDemoPayload())
        let embedded = try XCTUnwrap(DemoWatchPayload.payload,
                                     "DemoWatchPayload.json does not decode")

        let a = try XCTUnwrap(fresh.regressionState)
        let b = try XCTUnwrap(embedded.regressionState,
                              "embedded demo payload has no model")

        XCTAssertEqual(b.selectedFeatures, a.selectedFeatures,
                       "Model rules changed — run testPrintFreshPayload and paste the result "
                       + "into DemoWatchPayload.json, or the watch screenshots will show "
                       + "different colors from the phone's.")
        XCTAssertEqual(b.coefficients.count, a.coefficients.count)
        for (i, expected) in a.coefficients.enumerated() {
            XCTAssertEqual(b.coefficients[i], expected, accuracy: 1e-6,
                           "coefficient \(i) drifted")
        }
    }

    private func freshDemoPayload() -> WatchSyncPayload? {
        guard let state = FeelsLikeRegression.fit(ratings: DemoMode.ratings()) else { return nil }
        return WatchSyncPayload(regressionState: state,
                                useFahrenheit: false,
                                scenarioActivity: 1, scenarioDress: 0, scenarioSun: 0,
                                places: [])
    }
}
