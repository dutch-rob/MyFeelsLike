// SPDX-License-Identifier: GPL-3.0-or-later
//
//  SettingsView.swift
//  MyFeelsLike
//

import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage(SettingsKey.useFahrenheit) private var useFahrenheit: Bool = false
    @AppStorage(SettingsKey.use12HourClock) private var use12Hour = false
    @AppStorage(SettingsKey.shareDataWithDevs) private var shareData: Bool = false

    // #10: which graph series to show. All default on.
    @AppStorage(GraphKey.temp)     private var graphTemp     = true
    @AppStorage(GraphKey.wetBulb)  private var graphWetBulb  = true
    @AppStorage(GraphKey.dewPoint) private var graphDewPoint = true
    @AppStorage(GraphKey.feels)    private var graphFeels    = true
    @AppStorage(GraphKey.color)   private var graphColor   = true
    @AppStorage(GraphKey.precip)   private var graphPrecip   = true
    @AppStorage(GraphKey.wind)     private var graphWind     = true
    @AppStorage(GraphKey.gust)     private var graphGust     = true
    @AppStorage(GraphKey.sky)      private var graphSky      = true
    @AppStorage(SettingsKey.showTable)       private var showTable     = true
    @AppStorage(SettingsKey.compareName)     private var compareName   = ""
    @AppStorage(SettingsKey.sunShadeStyle)   private var sunShadeStyle  = SunShadeStyle.separate

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var ratings: [Rating]

    /// Currently-displayed forecast + place name, for the temporary developer
    /// aid that exports the forecast table as CSV.
    var forecast: [ForecastPoint] = []
    var placeName: String = ""

    @State private var showResetConfirm = false
    @State private var showInfo = false

    @State private var exportURL: URL? = nil
    @State private var showExportShare = false
    @State private var exportError: String? = nil

    @State private var showImportPicker = false
    @State private var importMessage: String? = nil

    /// Placeholder shown in the compare-name field (the device name).
    private var defaultCompareName: String {
        let n = UIDevice.current.name
        return n.isEmpty ? "MyFeelsLike user" : n
    }

    var body: some View {
        Form {
            Section("Units") {
                Picker("Temperature", selection: $useFahrenheit) {
                    Text("Celsius (°C)").tag(false)
                    Text("Fahrenheit (°F)").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("Time", selection: $use12Hour) {
                    Text("24-hour").tag(false)
                    Text("12-hour").tag(true)
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle("Temperature", isOn: $graphTemp)
                Toggle("Wet bulb", isOn: $graphWetBulb)
                Toggle("Dew point", isOn: $graphDewPoint)
                Toggle("Feels like line", isOn: $graphFeels)
                Toggle("MyFeelsLike color", isOn: $graphColor)
                Toggle("Precipitation", isOn: $graphPrecip)
                Toggle("Wind", isOn: $graphWind)
                Toggle("Gust", isOn: $graphGust)
                Toggle("Weather sky background", isOn: $graphSky)
            } header: {
                Text("Graphs")
            } footer: {
                Text("Choose which series to show. Emptying a panel hides it; turning everything off leaves just the table.")
            }

            Section {
                Toggle("Table screen", isOn: $showTable)
            } footer: {
                Text("When off, swiping only switches between the 24-hour and 10-day graph screens.")
            }

            Section {
                Picker("In sun vs in shade", selection: $sunShadeStyle) {
                    Text("Separate").tag(SunShadeStyle.separate)
                    Text("Gradient").tag(SunShadeStyle.gradient)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Sun / shade")
            } footer: {
                Text("How the color band shows in-sun vs in-shade when your model has learned a sun effect. Separate draws two bands (shade, and sun by daytime). Gradient blends shade→sun inside each cell — compact, but takes a moment to read.")
            }

            Section {
                TextField("Your name", text: $compareName, prompt: Text(defaultCompareName))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
            } header: {
                Text("Compare")
            } footer: {
                Text("Shown to others when you compare nearby. Leave blank to use your device name.")
            }

            Section {
                Toggle("Share data with developers", isOn: $shareData)
            } header: {
                Text("Sharing")
            } footer: {
                Text("Uploads your ratings (feels-like score, activity/dress/sun, and the weather at that moment) and your model coefficients anonymously — only a random per-install ID, no name, location, or place. Turning it off deletes what this install shared.")
            }

            Section {
                Button {
                    exportRatings()
                } label: {
                    Label("Export ratings as JSON…", systemImage: "square.and.arrow.up")
                }
                .disabled(ratings.isEmpty)

                Text("Export the data of this app as a JSON file — share it to e.g. an email, or save it to a folder in your iCloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let exportError {
                    Text(exportError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    importMessage = nil
                    showImportPicker = true
                } label: {
                    Label("Import ratings from JSON…", systemImage: "square.and.arrow.down")
                }

                Text("Import ratings from a previously exported JSON file. Ratings already present (matched by ID) are skipped — safe to re-import.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let importMessage {
                    Text(importMessage)
                        .font(.caption)
                        .foregroundStyle(importMessage.hasPrefix("Import failed") ? .red : .secondary)
                }

                Button {
                    exportForecast()
                } label: {
                    Label("Export forecast table (CSV)…", systemImage: "tablecells")
                }
                .disabled(forecast.isEmpty)

                Text("Temporary developer aid: exports the forecast currently shown for \(placeName.isEmpty ? "this place" : placeName) as a CSV file (hourly, 10 days) so it can be inspected or sent to the developer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Data")
            }

            Section("Your model") {
                LabeledContent("Ratings recorded", value: "\(ratings.count)")
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("Reset ratings & model", systemImage: "trash")
                }
                .disabled(ratings.isEmpty)
            }

            Section {
                Button {
                    showInfo = true
                } label: {
                    Label("About MyFeelsLike", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .confirmationDialog(
            "Delete all \(ratings.count) ratings?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete all ratings", role: .destructive) {
                resetRatings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes every rating you've given and clears the personalized model. This cannot be undone.")
        }
        .sheet(isPresented: $showInfo) {
            NavigationStack { InfoView() }
        }
        .sheet(isPresented: $showExportShare) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showImportPicker) {
            DocumentPicker(contentTypes: [.json]) { url in
                importRatings(from: url)
            }
        }
    }

    // MARK: - Reset

    private func resetRatings() {
        for r in ratings { modelContext.delete(r) }
        try? modelContext.save()
    }

    // MARK: - Export

    private func exportRatings() {
        exportError = nil
        do {
            let url = try writeExportJSON(ratings: ratings)
            exportURL = url
            showExportShare = true
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
        }
    }

    private func writeExportJSON(ratings: [Rating]) throws -> URL {
        let state = RegressionStateStore.load()
        let full = FullExport(
            exportedAt: Date(),
            model: state.map { ModelExport(from: $0, ratings: ratings) },
            ratings: ratings.map { RatingExport(from: $0, state: state) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(full)

        let stamp = Self.fileStampFormatter.string(from: Date())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyFeelsLike-export-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Forecast export (temporary developer aid)

    private func exportForecast() {
        exportError = nil
        do {
            let url = try writeForecastCSV(forecast: forecast, placeName: placeName)
            exportURL = url
            showExportShare = true
        } catch {
            exportError = "Forecast export failed: \(error.localizedDescription)"
        }
    }

    private func writeForecastCSV(forecast: [ForecastPoint], placeName: String) throws -> URL {
        let iso = ISO8601DateFormatter()
        func f(_ v: Double) -> String { String(format: "%.2f", v) }
        var lines = ["date,tempC,apparentC,wetBulbC,dewPointC,humidity,windKPH,gustKPH,precipProb,precipMM,cloud,cloudLow,cloudMed,cloudHigh,uv,pressurePa,isDaylight,symbol"]
        for p in forecast {
            lines.append([
                iso.string(from: p.date),
                f(p.temperatureC), f(p.apparentTemperatureC), f(p.wetBulbC), f(p.dewPointC),
                f(p.humidity), f(p.windSpeedKPH), f(p.windGustKPH),
                f(p.precipProbability), f(p.precipitationMM),
                f(p.cloudCover), f(p.cloudCoverLow), f(p.cloudCoverMedium), f(p.cloudCoverHigh),
                f(p.uvIndex), f(p.stationPressurePa), p.isDaylight ? "1" : "0", p.symbolName
            ].joined(separator: ","))
        }
        let data = Data(lines.joined(separator: "\n").utf8)

        let stamp = Self.fileStampFormatter.string(from: Date())
        let safePlace = placeName.isEmpty ? "place"
            : placeName.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyFeelsLike-forecast-\(safePlace)-\(stamp).csv")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Import

    private func importRatings(from url: URL) {
        importMessage = nil
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let existingIDs = Set(ratings.map { $0.id })
            let result = try decodeRatingsForImport(data: data, existingIDs: existingIDs)
            for r in result.toInsert { modelContext.insert(r) }
            try? modelContext.save()
            let added = result.toInsert.count
            importMessage = "Added \(added) rating\(added == 1 ? "" : "s")" +
                (result.skippedCount > 0 ? ", \(result.skippedCount) already present." : ".")
        } catch {
            importMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private static let fileStampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd-HHmm"
        return df
    }()
}

// MARK: - Top-level export envelope

/// Root object written to the JSON file.
struct FullExport: Codable {
    let exportedAt: Date
    /// Current regression model — null when fewer than 5 ratings exist.
    let model: ModelExport?
    let ratings: [RatingExport]
}

// MARK: - Model export

struct ModelExport: Codable {
    let fittedAt: Date
    let ratingCount: Int
    let rSquared: Double
    let aicc: Double
    /// Names of selected features in model order (apparentTempC always first).
    let features: [String]
    let intercept: CoefficientPair
    /// One entry per selected feature, in model order.
    let coefficients: [FeatureCoefficient]
    /// Leverage statistics computed over the training ratings.
    let diagnostics: LeverageDiagnostics

    struct CoefficientPair: Codable {
        /// Standardised (z-scored) coefficient.
        let std_coef: Double
        /// Unstandardised (original-units) coefficient.
        let raw_coef: Double
    }

    struct FeatureCoefficient: Codable {
        let feature: String
        let std_coef: Double
        let raw_coef: Double
    }

    struct LeverageDiagnostics: Codable {
        /// Number of model parameters (features + intercept).
        let m: Int
        /// Lower threshold 2m/n — model used as-is below this.
        let h_lower: Double
        /// Upper threshold 3m/n — falls back to apparent temperature above this.
        let h_upper: Double
        let h_min: Double
        let h_mean: Double
        let h_max: Double
        /// Training ratings whose leverage h ≤ h_lower (fully in-range).
        let n_inRange: Int
        /// Training ratings in the blend zone h_lower < h ≤ h_upper.
        let n_blended: Int
        /// Training ratings with h > h_upper (model would extrapolate).
        let n_extrapolated: Int
    }

    init(from state: RegressionState, ratings: [Rating]) {
        fittedAt    = state.lastFitAt
        ratingCount = state.ratingCount
        rSquared    = state.rSquared
        aicc        = state.aicc
        features    = state.selectedFeatures.map { $0.rawValue }

        // Intercept: convert standardised β₀ back to original scale.
        var rawInt = state.coefficients[0]
        for (i, _) in state.selectedFeatures.enumerated() {
            rawInt -= state.coefficients[i + 1] * state.means[i] / state.stds[i]
        }
        intercept = CoefficientPair(std_coef: state.coefficients[0], raw_coef: rawInt)

        // Per-feature coefficients.
        coefficients = state.selectedFeatures.enumerated().map { idx, f in
            let beta = state.coefficients[idx + 1]
            return FeatureCoefficient(
                feature:  f.rawValue,
                std_coef: beta,
                raw_coef: beta / state.stds[idx]
            )
        }

        // Leverage diagnostics over the training ratings.
        let n      = ratings.count
        let m      = state.selectedFeatures.count + 1
        let lower  = 2.0 * Double(m) / Double(n)
        let upper  = 3.0 * Double(m) / Double(n)
        let hs     = ratings.compactMap { state.leverage($0) }
        let hMin   = hs.min() ?? 0
        let hMax   = hs.max() ?? 0
        let hMean  = hs.isEmpty ? 0 : hs.reduce(0, +) / Double(hs.count)

        diagnostics = LeverageDiagnostics(
            m:               m,
            h_lower:         lower,
            h_upper:         upper,
            h_min:           hMin,
            h_mean:          hMean,
            h_max:           hMax,
            n_inRange:       hs.filter { $0 <= lower }.count,
            n_blended:       hs.filter { $0 > lower && $0 <= upper }.count,
            n_extrapolated:  hs.filter { $0 > upper }.count
        )
    }
}

// MARK: - Per-rating export

struct RatingExport: Codable {
    // Identity
    let id: UUID
    let timestamp: Date
    let placeID: UUID?

    // User input
    let feelsLikeScore: Double   // 0…1000 color-scale rating
    let activity: Int
    let dress: Int
    let sun: Int

    // Weather snapshot at time of rating
    let temperatureC: Double
    let apparentTemperatureC: Double
    let wetBulbC: Double
    let dewPointC: Double
    let humidity: Double
    let stationPressurePa: Double
    let windSpeedKPH: Double
    let precipProbability: Double
    let precipitationMM: Double
    let cloudCover: Double
    let cloudCoverLow: Double
    let cloudCoverMedium: Double
    let cloudCoverHigh: Double
    let uvIndex: Double
    let isDaylight: Bool

    // Model diagnostics (nil when no model was active at export time)
    /// Model's predicted score (0…1000) for this rating's feature values.
    let modelPredictionScore: Double?
    /// Hat-matrix diagonal h = x'(X'X)⁻¹x — how far this point is from
    /// the training centroid in feature space.
    let leverage_h: Double?
    /// Visual opacity of the model prediction (1 = fully reliable, 0 = beyond
    /// extrapolation threshold).
    let predictionOpacity: Double?

    init(from r: Rating, state: RegressionState?) {
        id                   = r.id
        timestamp            = r.timestamp
        placeID              = r.placeID
        feelsLikeScore       = r.feelsLikeScore
        activity             = r.activity
        dress                = r.dress
        sun                  = r.sun
        temperatureC         = r.temperatureC
        apparentTemperatureC = r.apparentTemperatureC
        wetBulbC             = r.wetBulbC
        dewPointC            = r.dewPointC
        humidity             = r.humidity
        stationPressurePa    = r.stationPressurePa
        windSpeedKPH         = r.windSpeedKPH
        precipProbability    = r.precipProbability
        precipitationMM      = r.precipitationMM
        cloudCover           = r.cloudCover
        cloudCoverLow        = r.cloudCoverLow
        cloudCoverMedium     = r.cloudCoverMedium
        cloudCoverHigh       = r.cloudCoverHigh
        uvIndex              = r.uvIndex
        isDaylight           = r.isDaylight

        if let state {
            modelPredictionScore = state.predict(r)
            leverage_h           = state.leverage(r)
            predictionOpacity    = state.predictionOpacity(r)
        } else {
            modelPredictionScore = nil
            leverage_h           = nil
            predictionOpacity    = nil
        }
    }
}

extension RatingExport {
    /// Reconstructs the original Rating, preserving id/timestamp so
    /// re-imports (matched by id) are idempotent. This is the exact
    /// field-by-field inverse of `init(from:state:)` above, kept as one
    /// function rather than duplicated inline at the import call site —
    /// otherwise the two field lists could silently drift apart (e.g. a
    /// field added to `Rating` but missed here) and a restored backup
    /// would quietly lose data with no error and nothing visibly wrong.
    func makeRating() -> Rating {
        Rating(
            id: id, timestamp: timestamp, placeID: placeID,
            feelsLikeScore: feelsLikeScore, activity: activity, dress: dress, sun: sun,
            temperatureC: temperatureC, apparentTemperatureC: apparentTemperatureC,
            wetBulbC: wetBulbC, dewPointC: dewPointC, humidity: humidity,
            stationPressurePa: stationPressurePa, windSpeedKPH: windSpeedKPH,
            precipProbability: precipProbability, precipitationMM: precipitationMM,
            cloudCover: cloudCover, cloudCoverLow: cloudCoverLow,
            cloudCoverMedium: cloudCoverMedium, cloudCoverHigh: cloudCoverHigh,
            uvIndex: uvIndex, isDaylight: isDaylight
        )
    }
}

// MARK: - Import decoding (pure, testable without a live SwiftData context)

/// Result of decoding an import file: ratings ready to insert, plus how many
/// were skipped because a rating with that id already exists.
struct ImportDecodeResult {
    let toInsert: [Rating]
    let skippedCount: Int
}

/// Decodes an exported ratings file and filters out ratings already present
/// (matched by id, so re-importing the same file twice is a no-op the second
/// time). Accepts both the current `FullExport` envelope and the legacy flat
/// `[RatingExport]` array some older exports used.
///
/// Kept free of SwiftUI/SwiftData so the decode-and-dedup logic — including
/// the legacy-format fallback, which silently swallows the primary decode
/// error via `try?` — can be exercised directly in tests instead of only
/// through a live import in the app.
func decodeRatingsForImport(data: Data, existingIDs: Set<UUID>) throws -> ImportDecodeResult {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let exports: [RatingExport]
    if let full = try? decoder.decode(FullExport.self, from: data) {
        exports = full.ratings
    } else {
        exports = try decoder.decode([RatingExport].self, from: data)
    }

    var toInsert: [Rating] = []
    var skipped = 0
    for e in exports {
        if existingIDs.contains(e.id) {
            skipped += 1
        } else {
            toInsert.append(e.makeRating())
        }
    }
    return ImportDecodeResult(toInsert: toInsert, skippedCount: skipped)
}

// MARK: - UIKit document-picker bridge (import)

private struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}

// MARK: - UIKit share-sheet bridge (export)

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
