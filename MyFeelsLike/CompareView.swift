//
//  CompareView.swift
//  MyFeelsLike
//
//  Phase 1 scaffold of the "Compare with:" screen: the entry points for
//  linking with other users (nearby / via text) plus the user's own
//  MyFeelsLike colour band. The networking (live nearby link, text invite,
//  peer model exchange) lands in later phases — for now the two buttons are
//  placeholders and only the user's own band is shown.
//

import SwiftUI
import Charts

// MARK: - Bottom-bar icon

/// Compare icon for the bottom bar: two people over a two-tone MyFeelsLike bar
/// (green-yellow vs yellow-orange) — "compare your colours with someone".
/// The people follow the bar tint; the colour swatch keeps its own colours.
struct CompareIcon: View {
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 12))
            HStack(spacing: 0) {
                Rectangle().fill(ColorScale.color(forScore: 300))   // green-yellow
                Rectangle().fill(ColorScale.color(forScore: 420))   // yellow-orange
            }
            .frame(width: 24, height: 7)
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

// MARK: - Colour band + row

/// A thin horizontal MyFeelsLike colour band over a 24h series (one cell per
/// hour). Grey placeholder when there's no personalised model yet.
struct FeelsBand: View {
    let series: [ForecastPoint]

    private var domain: ClosedRange<Date>? {
        guard let f = series.first?.date, let l = series.last?.date, f < l else { return nil }
        return f...l
    }
    private var hasColour: Bool { series.contains { $0.myFeelsLikeScore != nil } }

    var body: some View {
        Group {
            if let domain, hasColour {
                Chart(series) { p in
                    RectangleMark(
                        xStart: .value("t0", p.date.addingTimeInterval(-3600)),
                        xEnd:   .value("t1", p.date),
                        yStart: .value("y0", 0), yEnd: .value("y1", 1))
                    .foregroundStyle(colour(p))
                }
                .chartYScale(domain: 0...1)
                .chartYAxis(.hidden)
                .chartXAxis(.hidden)
                .chartXScale(domain: domain)
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.2))
                    .overlay(Text("No colour yet").font(.caption2).foregroundStyle(.secondary))
            }
        }
        .frame(height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func colour(_ p: ForecastPoint) -> Color {
        guard let s = p.myFeelsLikeScore else { return Color.gray.opacity(0.25) }
        return ColorScale.color(forScore: s).opacity(max(0.25, min(1, p.myFeelsLikeOpacity)))
    }
}

/// One labelled colour band in the compare list (a user's name + their band).
struct CompareBandRow: View {
    let name: String
    let series: [ForecastPoint]
    var ink: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.caption.weight(.medium)).foregroundStyle(ink)
            FeelsBand(series: series)
        }
    }
}

// MARK: - Compare screen

struct CompareView: View {
    /// The phone user's own personalised 24h series (for their colour band).
    let ownSeries: [ForecastPoint]
    /// Legible text colour over the weather-sky background.
    var ink: Color = .primary

    @State private var showComingSoon = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Compare with:")
                    .font(.headline).foregroundStyle(ink)

                // Two entry points (wired up in later phases).
                HStack(spacing: 12) {
                    Button { showComingSoon = true } label: {
                        Label("Connect Nearby", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    Button { showComingSoon = true } label: {
                        Label("Invite via Text", systemImage: "message")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .font(.footnote)

                Divider()

                // Phase 1: only the user's own band. Peers' bands join here once
                // linking is implemented.
                CompareBandRow(name: "You", series: ownSeries, ink: ink)

                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Coming soon", isPresented: $showComingSoon) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Linking with other users is being built. This screen is the first step.")
        }
    }
}
