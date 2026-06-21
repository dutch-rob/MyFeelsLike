#!/usr/bin/env swift
//
//  run_simulation.swift
//  MyFeelsLike — standalone regression simulation
//
//  Run from Terminal (no simulator, no Xcode build):
//
//    swift "/Users/dutchrob/Library/Mobile Documents/com~apple~CloudDocs/xcode/MyFeelsLike/run_simulation.swift"
//
//  Reads every .csv from MyFeelsLikeTests/simulated_ratings/,
//  runs a growing-window analysis (n = 5 … N),
//  and writes one tab-delimited .tsv alongside each .csv.
//
//  Output format (one row per n-step, one .tsv per .csv):
//
//    n  status  R2  AICc  nFeatures  features
//    b0_std  b0_raw
//    {feature}_std  {feature}_raw  (one column pair per Feature in allCases order)
//    m  h_lower  h_upper
//    h_min  h_mean  h_max  n_inRange  n_blended  n_extrapolated
//
//  "In range"    h ≤ 2m/n  — pure model used
//  "Blended"     2m/n < h ≤ 3m/n  — model blended with apparent temperature
//  "Extrapolated"  h > 3m/n  — falls back to apparent temperature
//
//  The regression logic is kept in sync with FeelsLikeRegression.swift.
//

import Foundation

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Simplified Rating (no SwiftData @Model needed for computation)
// ════════════════════════════════════════════════════════════════════════════

struct Rating {
    var feelsLikeC: Double
    var apparentTemperatureC: Double
    var temperatureC: Double
    var wetBulbC: Double
    var dewPointC: Double
    var humidity: Double          // 0…1
    var stationPressurePa: Double
    var windSpeedKPH: Double
    var precipProbability: Double
    var precipitationMM: Double
    var cloudCover: Double
    var cloudCoverLow: Double
    var cloudCoverMedium: Double
    var cloudCoverHigh: Double
    var uvIndex: Double
    var isDaylight: Bool
    var activity: Int
    var dress: Int
    var sun: Int
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Feature definitions
// ════════════════════════════════════════════════════════════════════════════

enum Feature: String, CaseIterable {
    case apparentTempC
    case apparentMinusTemp
    case tempMinusWetBulb
    case wetBulbMinusDewPoint
    case humidity
    case stationPressurePa
    case windSpeedKPH
    case precipProbability
    case precipitationMM
    case cloudCover
    case cloudCoverLow
    case cloudCoverMedium
    case cloudCoverHigh
    case uvIndex
    case isDaylight
    case activity
    case dress
    case sun

    static var candidates: [Feature] { allCases.filter { $0 != .apparentTempC } }
}

protocol FeatureSource { func value(for f: Feature) -> Double }

extension Rating: FeatureSource {
    func value(for f: Feature) -> Double {
        switch f {
        case .apparentTempC:        return apparentTemperatureC
        case .apparentMinusTemp:    return apparentTemperatureC - temperatureC
        case .tempMinusWetBulb:     return temperatureC - wetBulbC
        case .wetBulbMinusDewPoint: return wetBulbC - dewPointC
        case .humidity:             return humidity
        case .stationPressurePa:    return stationPressurePa
        case .windSpeedKPH:         return windSpeedKPH
        case .precipProbability:    return precipProbability
        case .precipitationMM:      return precipitationMM
        case .cloudCover:           return cloudCover
        case .cloudCoverLow:        return cloudCoverLow
        case .cloudCoverMedium:     return cloudCoverMedium
        case .cloudCoverHigh:       return cloudCoverHigh
        case .uvIndex:              return uvIndex
        case .isDaylight:           return isDaylight ? 1 : 0
        case .activity:             return Double(activity)
        case .dress:                return Double(dress)
        case .sun:                  return Double(sun)
        }
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - RegressionState
// ════════════════════════════════════════════════════════════════════════════

struct RegressionState {
    var selectedFeatures: [Feature]
    var coefficients: [Double]   // β0 (intercept) + one per selectedFeature
    var means: [Double]
    var stds: [Double]
    var rSquared: Double
    var aicc: Double
    var ratingCount: Int
    var invXtX: [[Double]]       // (X'X)⁻¹ in standardised space, for leverage

    /// Leverage h = x'(X'X)⁻¹x for a query point (hat-matrix diagonal).
    func leverage(_ src: FeatureSource) -> Double {
        let m = selectedFeatures.count + 1
        var x = [Double](repeating: 0, count: m)
        x[0] = 1.0
        for (j, f) in selectedFeatures.enumerated() {
            x[j + 1] = (src.value(for: f) - means[j]) / stds[j]
        }
        var h = 0.0
        for i in 0..<m {
            var s = 0.0
            for k in 0..<m { s += invXtX[i][k] * x[k] }
            h += x[i] * s
        }
        return h
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - FeelsLikeRegression (synced with FeelsLikeRegression.swift)
// ════════════════════════════════════════════════════════════════════════════

enum FeelsLikeRegression {

    static func canFit(ratings: [Rating]) -> Bool {
        guard ratings.count >= 5 else { return false }
        let ys = ratings.map { $0.feelsLikeC }
        guard let lo = ys.min(), let hi = ys.max() else { return false }
        return (hi - lo) >= 5.0
    }

    static func featureBudget(n: Int) -> Int {
        let raw = (n - 5) / 5
        let cap = max(0, (n - 2) / 3 - 1)
        return max(0, min(raw, cap))
    }

    static func fit(ratings: [Rating]) -> RegressionState? {
        guard canFit(ratings: ratings) else { return nil }
        let budget = featureBudget(n: ratings.count)
        var selected: [Feature] = [.apparentTempC]
        guard var best = fitOLS(ratings: ratings, features: selected) else { return nil }
        var remaining = Set(Feature.candidates)
        for _ in 0..<budget {
            var pick: (Feature, RegressionState)?
            for f in remaining {
                guard let st = fitOLS(ratings: ratings, features: selected + [f]) else { continue }
                if pick == nil || st.aicc < pick!.1.aicc { pick = (f, st) }
            }
            guard let p = pick, p.1.aicc + 2.0 < best.aicc else { break }
            selected.append(p.0); remaining.remove(p.0); best = p.1
        }
        return best
    }

    static func fitOLS(ratings: [Rating], features: [Feature]) -> RegressionState? {
        let n = ratings.count, p = features.count
        guard n > p + 1 else { return nil }

        var raw = Array(repeating: Array(repeating: 0.0, count: p), count: n)
        var y   = Array(repeating: 0.0, count: n)
        for (i, r) in ratings.enumerated() {
            for (j, f) in features.enumerated() { raw[i][j] = r.value(for: f) }
            y[i] = r.feelsLikeC
        }

        var means = Array(repeating: 0.0, count: p)
        var stds  = Array(repeating: 0.0, count: p)
        for j in 0..<p {
            let col = (0..<n).map { raw[$0][j] }
            let m = col.reduce(0, +) / Double(n); means[j] = m
            let v = col.reduce(0) { $0 + ($1-m)*($1-m) } / Double(n-1)
            stds[j] = max(sqrt(v), 1e-9)
        }

        let m = p + 1
        var Xstd = Array(repeating: Array(repeating: 0.0, count: m), count: n)
        for i in 0..<n {
            Xstd[i][0] = 1.0
            for j in 0..<p { Xstd[i][j+1] = (raw[i][j] - means[j]) / stds[j] }
        }

        var XtX = Array(repeating: Array(repeating: 0.0, count: m), count: m)
        var Xty = Array(repeating: 0.0, count: m)
        for i in 0..<n {
            for a in 0..<m {
                Xty[a] += Xstd[i][a] * y[i]
                for b in a..<m { XtX[a][b] += Xstd[i][a] * Xstd[i][b] }
            }
        }
        for a in 0..<m { for b in 0..<a { XtX[a][b] = XtX[b][a] } }

        guard let L = cholesky(XtX) else { return nil }
        let beta = cholSolve(L: L, b: Xty)

        // Compute (X'X)⁻¹ via repeated Cholesky solves on unit vectors.
        var inv = Array(repeating: Array(repeating: 0.0, count: m), count: m)
        for j in 0..<m {
            var e = Array(repeating: 0.0, count: m); e[j] = 1
            let col = cholSolve(L: L, b: e)
            for i in 0..<m { inv[i][j] = col[i] }
        }

        var rss = 0.0
        for i in 0..<n {
            var yhat = 0.0; for a in 0..<m { yhat += Xstd[i][a] * beta[a] }
            let r = y[i] - yhat; rss += r * r
        }
        let yMean = y.reduce(0,+) / Double(n)
        let tss   = y.reduce(0) { $0 + ($1-yMean)*($1-yMean) }
        let r2    = tss > 1e-12 ? 1 - rss/tss : 0
        let nD = Double(n), pD = Double(m)
        let aic  = nD * log(max(rss,1e-12)/nD) + 2*pD
        let corr = nD - pD - 1 > 0 ? 2*pD*(pD+1)/(nD-pD-1) : Double.infinity

        return RegressionState(selectedFeatures: features, coefficients: beta,
                               means: means, stds: stds,
                               rSquared: r2, aicc: aic+corr,
                               ratingCount: n, invXtX: inv)
    }

    static func cholesky(_ A: [[Double]]) -> [[Double]]? {
        let m = A.count
        var L = Array(repeating: Array(repeating: 0.0, count: m), count: m)
        for i in 0..<m { for j in 0...i {
            var s = A[i][j]; for k in 0..<j { s -= L[i][k]*L[j][k] }
            if i == j { if s <= 1e-12 { return nil }; L[i][j] = sqrt(s) }
            else       { L[i][j] = s / L[j][j] }
        }}
        return L
    }

    static func cholSolve(L: [[Double]], b: [Double]) -> [Double] {
        let m = L.count
        var ys = Array(repeating: 0.0, count: m)
        for i in 0..<m { var s = b[i]; for k in 0..<i { s -= L[i][k]*ys[k] }; ys[i] = s/L[i][i] }
        var x = Array(repeating: 0.0, count: m)
        for ii in 0..<m { let i = m-1-ii; var s = ys[i]
            for k in (i+1)..<m { s -= L[k][i]*x[k] }; x[i] = s/L[i][i] }
        return x
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - CSV parser
// ════════════════════════════════════════════════════════════════════════════

func parseCSV(_ url: URL) throws -> [Rating] {
    var out = [Rating]()
    for line in (try String(contentsOf: url, encoding: .utf8)).components(separatedBy: .newlines) {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !t.hasPrefix("#") else { continue }
        let c = t.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard c.count >= 9,
              let v0 = Double(c[0]), let v1 = Double(c[1]), let v2 = Double(c[2]),
              let v3 = Double(c[3]), let v4 = Double(c[4]), let v5 = Double(c[5]),
              let v6 = Double(c[6]), let v7 = Double(c[7]), let v8 = Double(c[8])
        else { continue }
        out.append(Rating(feelsLikeC: v0, apparentTemperatureC: v1, temperatureC: v2,
                          wetBulbC: v4, dewPointC: v3, humidity: v5/100.0,
                          stationPressurePa: 101_325, windSpeedKPH: v8,
                          precipProbability: 0, precipitationMM: v7,
                          cloudCover: v6, cloudCoverLow: 0, cloudCoverMedium: 0,
                          cloudCoverHigh: 0, uvIndex: 0, isDaylight: true,
                          activity: 1, dress: 0, sun: 0))
    }
    return out
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - TSV output helpers
// ════════════════════════════════════════════════════════════════════════════

/// All feature names in canonical order — determines column layout.
let allFeatures = Feature.allCases

/// Column headers (call once per file).
func tsvHeader() -> String {
    var cols = ["n", "status", "R2", "AICc", "nFeatures", "features",
                "b0_std", "b0_raw"]
    for f in allFeatures {
        cols.append("\(f.rawValue)_std")
        cols.append("\(f.rawValue)_raw")
    }
    cols += ["m", "h_lower", "h_upper",
             "h_min", "h_mean", "h_max",
             "n_inRange", "n_blended", "n_extrapolated"]
    return cols.joined(separator: "\t")
}

/// One TSV data row for a given n and rating window.
func tsvRow(n: Int, ratings: [Rating]) -> String {
    var cols: [String] = []
    let fmt2 = { (v: Double) in String(format: "%.4f", v) }
    let fmt4 = { (v: Double) in String(format: "%.4f", v) }

    cols.append("\(n)")   // n

    guard FeelsLikeRegression.canFit(ratings: ratings) else {
        // NO MODEL row
        let ys = ratings.map { $0.feelsLikeC }
        let sp = (ys.max() ?? 0) - (ys.min() ?? 0)
        let why = ratings.count < 5 ? "fewer_than_5"
                                    : String(format: "spread_%.2fC", sp)
        cols.append("NO_MODEL(\(why))")
        // Pad remaining columns with empty strings
        let remaining = 6 + allFeatures.count * 2 + 9
        cols += Array(repeating: "", count: remaining)
        return cols.joined(separator: "\t")
    }

    guard let st = FeelsLikeRegression.fit(ratings: ratings) else {
        cols.append("FIT_FAILED")
        let remaining = 6 + allFeatures.count * 2 + 9
        cols += Array(repeating: "", count: remaining)
        return cols.joined(separator: "\t")
    }

    // ── Model stats ──────────────────────────────────────────────────────────
    cols.append("MODEL")
    cols.append(fmt2(st.rSquared))
    cols.append(fmt2(st.aicc))
    cols.append("\(st.selectedFeatures.count)")
    cols.append(st.selectedFeatures.map { $0.rawValue }.joined(separator: ","))

    // ── Intercept ────────────────────────────────────────────────────────────
    let beta0 = st.coefficients[0]
    var rawIntercept = beta0
    for (i, _) in st.selectedFeatures.enumerated() {
        let bj = st.coefficients[i+1]
        rawIntercept -= bj * st.means[i] / st.stds[i]
    }
    cols.append(fmt4(beta0))
    cols.append(fmt4(rawIntercept))

    // ── Per-feature coefficients (fixed column layout) ───────────────────────
    let coefIndex = Dictionary(uniqueKeysWithValues:
        st.selectedFeatures.enumerated().map { ($1, $0) })
    for f in allFeatures {
        if let idx = coefIndex[f] {
            let betaJ = st.coefficients[idx + 1]
            let rawJ  = betaJ / st.stds[idx]
            cols.append(fmt4(betaJ))
            cols.append(fmt4(rawJ))
        } else {
            cols.append(""); cols.append("")
        }
    }

    // ── Leverage diagnostics on the training set ─────────────────────────────
    let m   = st.selectedFeatures.count + 1
    let nD  = Double(n)
    let mD  = Double(m)
    let lower = 2.0 * mD / nD
    let upper = 3.0 * mD / nD

    let hs = ratings.map { st.leverage($0) }
    let hMin  = hs.min()!
    let hMax  = hs.max()!
    let hMean = hs.reduce(0, +) / nD
    let nIn   = hs.filter { $0 <= lower }.count
    let nBl   = hs.filter { $0 > lower && $0 <= upper }.count
    let nEx   = hs.filter { $0 > upper }.count

    cols.append("\(m)")
    cols.append(fmt4(lower))
    cols.append(fmt4(upper))
    cols.append(fmt4(hMin))
    cols.append(fmt4(hMean))
    cols.append(fmt4(hMax))
    cols.append("\(nIn)")
    cols.append("\(nBl)")
    cols.append("\(nEx)")

    return cols.joined(separator: "\t")
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Main
// ════════════════════════════════════════════════════════════════════════════

let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
let simDir    = scriptDir.appendingPathComponent("MyFeelsLikeTests/simulated_ratings")
let fm        = FileManager.default

guard fm.fileExists(atPath: simDir.path) else {
    print("❌  simulated_ratings/ not found at:\n   \(simDir.path)"); exit(1)
}

let csvFiles = try fm.contentsOfDirectory(at: simDir, includingPropertiesForKeys: nil)
    .filter  { $0.pathExtension.lowercased() == "csv" }
    .sorted  { $0.lastPathComponent < $1.lastPathComponent }

guard !csvFiles.isEmpty else { print("❌  No CSV files found."); exit(1) }
print("Found \(csvFiles.count) CSV files — processing…\n")

for csvURL in csvFiles {
    let ratings = try parseCSV(csvURL)
    print("\(csvURL.lastPathComponent): \(ratings.count) data rows")

    var lines = [tsvHeader()]
    for n in 5...ratings.count {
        lines.append(tsvRow(n: n, ratings: Array(ratings.prefix(n))))
    }

    let tsvURL = csvURL.deletingPathExtension().appendingPathExtension("tsv")
    try lines.joined(separator: "\n").write(to: tsvURL, atomically: true, encoding: .utf8)
    print("  → \(tsvURL.lastPathComponent)")
}

print("""

✅  Done — .tsv files written alongside each .csv in simulated_ratings/

Column layout (tab-delimited):
  n, status, R2, AICc, nFeatures, features,
  b0_std, b0_raw,
  {feature}_std / {feature}_raw  for each of \(allFeatures.count) features (blank if not in model),
  m, h_lower (2m/n), h_upper (3m/n),
  h_min, h_mean, h_max,
  n_inRange (h ≤ lower), n_blended (lower < h ≤ upper), n_extrapolated (h > upper)
""")
