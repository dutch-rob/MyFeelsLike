//
//  SharedChartComponents.swift
//  MyFeelsLike
//
//  Pieces shared by the forecast screens (HereTodayView, TenDayView) and the
//  Compare screen: the loading view, the chart legend row, the WeatherKit
//  attribution link, the compact clock-hour formatter, the GraphKey settings
//  keys, the MyFeelsLike cell-color helpers, and a small View convenience.
//

import SwiftUI

// MARK: - Shared components

struct ForecastLoadingView: View {
    var progress: LoadProgress
    var nowTick: Date
    var errorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading forecast…")
                .foregroundStyle(.secondary)
                .font(.callout)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(LoadStep.allCases) { step in
                    HStack(spacing: 8) {
                        stepIcon(for: step)
                        Text(step.rawValue)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if case .inProgress(let t) = (progress.steps[step] ?? .pending),
                           nowTick.timeIntervalSince(t) > 2 {
                            Text("(working…)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func stepIcon(for step: LoadStep) -> some View {
        switch progress.steps[step] ?? .pending {
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .inProgress(let t):
            if nowTick.timeIntervalSince(t) > 2 {
                ProgressView().frame(width: 14, height: 14)
            } else {
                Image(systemName: "hourglass").foregroundStyle(.secondary)
            }
        case .failure:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .pending:
            Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
        }
    }
}

struct ChartLegendRow: View {
    let entries: [(color: Color, label: String, isArea: Bool)]
    /// Text color — follows the sky (black by day, white by night) so labels
    /// stay legible on the weather background.
    var ink: Color = .secondary

    var body: some View {
        // One line when the panel is wide enough; two lines in narrow panels
        // (e.g. three-across iPhone landscape) instead of wrapping mid-word.
        ViewThatFits(in: .horizontal) {
            row(entries)
            VStack(alignment: .leading, spacing: 2) {
                row(Array(entries.prefix((entries.count + 1) / 2)))
                row(Array(entries.suffix(entries.count / 2)))
            }
        }
    }

    @ViewBuilder
    private func row(_ items: [(color: Color, label: String, isArea: Bool)]) -> some View {
        HStack(spacing: 14) {
            ForEach(items, id: \.label) { e in
                HStack(spacing: 4) {
                    if e.isArea {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(e.color.opacity(0.4))
                            .frame(width: 18, height: 8)
                    } else {
                        Rectangle()
                            .fill(e.color)
                            .frame(width: 18, height: 2)
                    }
                    Text(e.label)
                        .font(.caption2)
                        .foregroundStyle(ink)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct WeatherAttributionLink: View {
    let info: WeatherAttributionInfo
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Link(destination: info.legalPageURL) {
            AsyncImage(
                url: colorScheme == .dark ? info.darkLogoURL : info.lightLogoURL
            ) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text("Apple Weather").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(height: 12)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Clock format

/// Compact hour-of-day label. 24-hour → "00"…"23". 12-hour → 1…12 with the
/// noon tick spelled out ("noon") and midnight shown as "12", no am/pm suffix.
func clockHourLabel(_ hour: Int, use12: Bool) -> String {
    let h = ((hour % 24) + 24) % 24
    guard use12 else { return String(format: "%02d", h) }
    if h == 12 { return "noon" }
    let hr = h % 12
    return hr == 0 ? "12" : "\(hr)"
}

// MARK: - Graph visibility settings (user-toggleable in Settings)

/// @AppStorage keys for which graph series the user wants to see. All default
/// to true. Shared by the forecast views, ContentView (tab gating) and Settings.
enum GraphKey {
    static let temp     = "graphTemp"
    static let wetBulb  = "graphWetBulb"
    static let dewPoint = "graphDewPoint"
    static let feels    = "graphFeels"
    static let color   = "graphColor"
    static let precip   = "graphPrecip"
    static let wind     = "graphWind"
    static let gust     = "graphGust"
    static let sky      = "graphSky"

    /// True when at least one graph series is enabled (any forecast panel would
    /// show). When false, the 24h/10-day screens are hidden entirely.
    static func anyGraphEnabled(_ d: UserDefaults = .standard) -> Bool {
        let all = [temp, wetBulb, dewPoint, feels, color, precip, wind, gust]
        // Missing key defaults to true (on).
        return all.contains { d.object(forKey: $0) == nil || d.bool(forKey: $0) }
    }
}

// MARK: - Personalized color background for the temperature chart

/// Cell color for the MyFeelsLike panels (24h strip + 10-day heatmap): the
/// score's color at full opacity. Reliability is conveyed by the cell's
/// width (see myFeelsLikeReliability), not by fading. Gray when no score.
func myFeelsLikeHeatColor(_ p: ForecastPoint) -> Color {
    ColorScale.feelsColor(score: p.myFeelsLikeScore, opacity: 1)
}

/// Prediction reliability in 0…1, used to scale a cell's width so uncertain
/// forecasts read as a thinner band rather than a fainter color. A small
/// floor keeps even the least reliable cell visible as a sliver.
func myFeelsLikeReliability(_ p: ForecastPoint) -> Double {
    guard p.myFeelsLikeScore != nil else { return 1 }
    return max(0.15, min(1, p.myFeelsLikeOpacity))
}


// MARK: - View extension

extension View {
    @ViewBuilder
    func ifLet<T, Content: View>(_ value: T?, transform: (Self, T) -> Content) -> some View {
        if let v = value { transform(self, v) } else { self }
    }
}
