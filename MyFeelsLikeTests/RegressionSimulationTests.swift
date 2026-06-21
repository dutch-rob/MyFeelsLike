//
//  RegressionSimulationTests.swift
//  MyFeelsLikeTests
//
//  Reads every .csv from the simulated_ratings/ bundle resource folder,
//  runs a growing-window regression analysis (n = 5 … 100 rows),
//  and writes one .txt report per CSV file to a temp folder.
//
//  Run in Xcode: Cmd+U, or right-click the test in the Test navigator.
//  Output .txt files are written to ~/Desktop/simulated_ratings_output/
//  and that folder is opened in Finder when the test completes.
//
//  CSV column order (one optional header row is skipped automatically):
//    1  feelsLikeC          °C     user rating
//    2  apparentTempC       °C
//    3  temperatureC        °C     dry-bulb
//    4  dewPointC           °C
//    5  wetBulbC            °C
//    6  humidity            %      (divided by 100 on import)
//    7  cloudCover          0–1    fraction
//    8  precipitationMM     mm
//    9  windSpeedKPH        kph
//

import Testing
import Foundation
@testable import MyFeelsLike

struct RegressionSimulationTests {

    @Test("Growing-window regression on all simulated_ratings/ CSV files")
    func runSimulations() throws {
        // ── Find all CSV files bundled with the test target ───────────────────
        let bundle   = Bundle(for: AnyClassFromThisBundle.self)
        let csvURLs  = bundle.urls(forResourcesWithExtension: "csv",
                                   subdirectory: "simulated_ratings") ?? []

        guard !csvURLs.isEmpty else {
            print("⚠️  No CSV resources found. Make sure simulated_ratings/ is")
            print("    inside MyFeelsLikeTests/ and Xcode has indexed the project.")
            return
        }
        print("\nFound \(csvURLs.count) CSV file(s)")

        // ── Output folder: ~/Desktop/simulated_ratings_output/ ────────────────
        let desktop   = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
        let outputDir = desktop.appendingPathComponent("simulated_ratings_output")
        try FileManager.default.createDirectory(at: outputDir,
                                                withIntermediateDirectories: true)

        // ── Process each file ─────────────────────────────────────────────────
        for csvURL in csvURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try processFile(csvURL, outputDir: outputDir)
        }

        print("\n✅ Reports written to:")
        print("   \(outputDir.path)")
        print("   Opening in Finder…\n")
        // Open the output folder in Finder (works when running on simulator host)
        #if os(iOS)
        // On-simulator: print path only (Finder open not available)
        #else
        NSWorkspace.shared.open(outputDir)
        #endif
    }

    // ── Process one CSV file ──────────────────────────────────────────────────

    private func processFile(_ csvURL: URL, outputDir: URL) throws {
        let allRatings = try parseCSV(csvURL)
        let baseName   = csvURL.deletingPathExtension().lastPathComponent
        print("  \(csvURL.lastPathComponent): \(allRatings.count) rows")

        guard !allRatings.isEmpty else {
            print("    ⚠️  No parseable rows — skipped"); return
        }

        // ── Header block ──────────────────────────────────────────────────────
        let divider = String(repeating: "─", count: 115)
        var lines   = [String]()
        lines.append("Regression simulation report")
        lines.append("File    : \(csvURL.lastPathComponent)")
        lines.append("Rows    : \(allRatings.count)")
        lines.append("Created : \(Date())")
        lines.append(divider)
        lines.append("Notes:")
        lines.append("  • Coefficients are for z-scored (standardised) features.")
        lines.append("  • The anchor feature (apparentTempC) is always in the model when one is fit.")
        lines.append("  • AICc = small-sample corrected Akaike criterion (lower = better fit).")
        lines.append(divider)
        lines.append(columnHeader())
        lines.append(divider)

        // ── Growing window n = 5 … N ──────────────────────────────────────────
        for n in 5...allRatings.count {
            lines.append(analysisLine(n: n, ratings: Array(allRatings.prefix(n))))
        }
        lines.append(divider)

        // ── Write .txt ────────────────────────────────────────────────────────
        let txtURL = outputDir.appendingPathComponent("\(baseName).txt")
        try lines.joined(separator: "\n")
            .write(to: txtURL, atomically: true, encoding: .utf8)
        print("    → \(txtURL.lastPathComponent)")
    }

    // ── Column header ─────────────────────────────────────────────────────────

    private func columnHeader() -> String {
        "n      status       R²      AICc        features selected & standardised coefficients"
    }

    // ── One analysis line ─────────────────────────────────────────────────────

    private func analysisLine(n: Int, ratings: [Rating]) -> String {
        let tag = String(format: "n=%3d  ", n)

        // Cannot fit?
        if !FeelsLikeRegression.canFit(ratings: ratings) {
            let reason: String
            if ratings.count < 5 {
                reason = "fewer than 5 ratings"
            } else {
                let ys     = ratings.map { $0.feelsLikeC }
                let spread = (ys.max() ?? 0) - (ys.min() ?? 0)
                reason     = String(format: "spread=%.2f°C (need ≥5.00°C)", spread)
            }
            return "\(tag)NO MODEL    \(reason)"
        }

        // Fit failed?
        guard let state = FeelsLikeRegression.fit(ratings: ratings) else {
            return "\(tag)FIT FAILED   singular matrix or collinear features"
        }

        // Format coefficients
        let featNames = state.selectedFeatures.map { $0.rawValue }
        var coefs     = [String(format: "β₀=%+.4f", state.coefficients[0])]
        for (i, name) in featNames.enumerated() {
            coefs.append(String(format: "%@=%+.4f", name, state.coefficients[i + 1]))
        }

        return String(format: "%@FIT          %.4f  %9.2f   [%@]  %@",
                      tag,
                      state.rSquared,
                      state.aicc,
                      featNames.joined(separator: ", "),
                      coefs.joined(separator: "  "))
    }

    // ── CSV parser ────────────────────────────────────────────────────────────

    private func parseCSV(_ url: URL) throws -> [Rating] {
        let raw  = try String(contentsOf: url, encoding: .utf8)
        var out  = [Rating]()

        for line in raw.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#") else { continue }

            let c = t.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard c.count >= 9,
                  let feelsLike  = Double(c[0]),
                  let apparentC  = Double(c[1]),
                  let tempC      = Double(c[2]),
                  let dewC       = Double(c[3]),
                  let wetBulbC   = Double(c[4]),
                  let humidPct   = Double(c[5]),
                  let cloudCover = Double(c[6]),
                  let precipMM   = Double(c[7]),
                  let windKPH    = Double(c[8])
            else { continue }   // skips header row and any malformed lines

            let snap = ForecastPoint(
                date:                 Date(),
                symbolName:           "sun.max",
                isDaylight:           true,
                uvIndex:              0,
                temperatureF:         tempC     * 9/5 + 32,
                temperatureC:         tempC,
                apparentTemperatureF: apparentC * 9/5 + 32,
                apparentTemperatureC: apparentC,
                wetBulbF:             wetBulbC  * 9/5 + 32,
                wetBulbC:             wetBulbC,
                dewPointF:            dewC      * 9/5 + 32,
                dewPointC:            dewC,
                precipProbability:    0,
                precipitationMM:      precipMM,
                windSpeedMPH:         windKPH / 1.60934,
                windSpeedKPH:         windKPH,
                cloudCover:           cloudCover,
                cloudCoverLow:        0,
                cloudCoverMedium:     0,
                cloudCoverHigh:       0,
                humidity:             humidPct / 100.0,
                stationPressurePa:    101_325,
                myFeelsLikeC:         nil,
                myFeelsLikeF:         nil
            )

            out.append(Rating(feelsLikeC: feelsLike,
                              activity:   1,
                              dress:      0,
                              sun:        0,
                              snapshot:   snap))
        }
        return out
    }
}

// Needed to call Bundle(for:) from a struct — any class from this module works.
private final class AnyClassFromThisBundle: NSObject {}
