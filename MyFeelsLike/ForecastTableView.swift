// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct ForecastTableView: View {
    @ObservedObject var weatherService: WeatherService
    var nowTick: Date
    var onRefresh: (() async -> Void)? = nil
    /// Applied to the 10-day series so the leftmost MyFeelsLike column reflects
    /// the personalized regression model when one exists.
    var personalize: ([ForecastPoint]) -> [ForecastPoint] = { $0 }
    /// Features currently in the regression model. Used to decide which
    /// scenario adjusters to display (matches the graph screens).
    var activeFeatures: Set<Feature>? = nil
    /// Called when the user swipes past an end of the table: -1 = previous
    /// screen, +1 = next. The table owns its own scrolling, so it switches
    /// screens on over-scroll rather than on any vertical drag.
    var onSwitchScreen: ((Int) -> Void)? = nil
    /// The moment showing at the top of the table, shared with the graph
    /// screens so switching between them keeps the same place in time. Read on
    /// the way in, written as the user scrolls.
    @Binding var topDate: Date?

    @State private var atTop = true
    @State private var atBottom = false
    /// False until the table has been scrolled to the graph's moment. The scroll
    /// observer fires during the first layout (reporting the top of the content)
    /// and would otherwise overwrite the very position we are about to restore.
    @State private var hasAligned = false

    private struct ScrollEdges: Equatable {
        var top: Bool
        var bottom: Bool
        /// How far down the content we are, 0…1.
        var fraction: Double
    }

    @AppStorage(SettingsKey.useFahrenheit) private var useFahrenheit: Bool = true
    @AppStorage(SettingsKey.use12HourClock) private var use12Hour = false

    private static let timeFormatter24: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "HH:mm"
        return df
    }()

    private static let timeFormatter12: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "h a"   // e.g. "2 PM" (rows are hourly)
        return df
    }()

    private func timeLabel(for date: Date) -> String {
        (use12Hour ? Self.timeFormatter12 : Self.timeFormatter24).string(from: date)
    }

    private static let dayHeaderFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = .current
        df.dateFormat = "EEEE d MMM"
        return df
    }()

    private struct DaySection: Identifiable {
        let id: String
        let title: String
        let points: [ForecastPoint]
    }

    /// Historic (past 24 h) → "now" → forecast, all personalized, in time order.
    private var allRows: [ForecastPoint] {
        var pts = personalize(weatherService.historic)
        if let c = weatherService.current { pts += personalize([c]) }
        pts += personalize(weatherService.series10d)
        return pts
    }

    private var daySections: [DaySection] {
        var sections: [DaySection] = []
        var currentKey  = ""
        var currentPts: [ForecastPoint] = []

        for pt in allRows {
            let key = Self.dayHeaderFormatter.string(from: pt.date)
            if key != currentKey {
                if !currentPts.isEmpty {
                    sections.append(DaySection(id: currentKey, title: currentKey, points: currentPts))
                }
                currentKey = key
                currentPts = [pt]
            } else {
                currentPts.append(pt)
            }
        }
        if !currentPts.isEmpty {
            sections.append(DaySection(id: currentKey, title: currentKey, points: currentPts))
        }
        return sections
    }

    /// Scroll to the moment the graph screen was showing, or to "now" when
    /// there isn't one.
    private func alignToGraph(_ proxy: ScrollViewProxy) {
        let target = topDate ?? nowTick
        guard let id = nearestForecastPoint(to: target, in: allRows)?.id else { return }
        // Two passes: in a LazyVStack the target row may not exist yet, and a
        // scrollTo to an unrealised row does nothing. The first jump realises
        // the rows around it, the second lands on it exactly.
        DispatchQueue.main.async {
            proxy.scrollTo(id, anchor: .topLeading)
            DispatchQueue.main.async {
                proxy.scrollTo(id, anchor: .topLeading)
                hasAligned = true
            }
        }
    }

    // Column widths (tweaked for narrower cloud column + extra space after MyFeel)
    private let wMyFL:   CGFloat = 70
    private let wTime:   CGFloat = 48
    private let wSym:    CGFloat = 26
    private let wUV:     CGFloat = 30
    private let wTemp:   CGFloat = 95
    private let wWet:    CGFloat = 62
    private let wDew:    CGFloat = 55
    private let wWind:   CGFloat = 78
    private let wPrecip: CGFloat = 82
    private let wCloud:  CGFloat = 110

    /// Right-padding applied to the MyFeel cell so its numbers sit further
    /// from the Time column (user-visible: extra breathing room between
    /// the two leftmost columns).
    private let myFLTrailingGap: CGFloat = 10

    private var totalWidth: CGFloat {
        wMyFL + myFLTrailingGap + wTime + wSym + wUV + wTemp + wWet + wDew + wWind + wPrecip + wCloud + 16
    }

    // MARK: - Data-text colors, adapted to the sky's day/night for contrast

    // The parent forces colorScheme to match the weather (light by day, dark by
    // night), so the value colors darken over the pale daytime sky and lighten
    // over the dark night sky — keeping the green/blue/red coding legible on both.
    @Environment(\.colorScheme) private var colorScheme

    /// A graph color shifted for contrast against the current background: mixed
    /// toward black by day, toward white by night.
    private func valueColor(_ base: Color) -> Color {
        colorScheme == .dark ? base.mix(with: .white, by: 0.35)
                             : base.mix(with: .black, by: 0.45)
    }
    private var cTemp:   Color { valueColor(.green) }
    private var cWet:    Color { valueColor(.blue) }
    private var cDew:    Color { valueColor(.red) }
    private var cWind:   Color { valueColor(.red) }
    private var cPrecip: Color { valueColor(.blue) }
    private var cMyFL:   Color { valueColor(.purple) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if weatherService.series10d.isEmpty || weatherService.isRefreshing {
                ForecastLoadingView(
                    progress: weatherService.loadProgress,
                    nowTick: nowTick,
                    errorMessage: weatherService.lastErrorMessage
                )
                .padding()
            } else {
                // Scenario adjusters (only those that are actually in the model)
                ScenarioStrip(activeFeatures: activeFeatures)

                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                            if weatherService.historicUnavailable {
                                Text("Past 10 days not available for this location.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)
                                    .padding(.vertical, 6)
                            }
                            ForEach(daySections) { section in
                                Section {
                                    ForEach(section.points) { point in
                                        dataRow(point)
                                            .background(rowBackground(point))
                                    }
                                } header: {
                                    VStack(spacing: 0) {
                                        Text(section.title)
                                            .font(.subheadline).fontWeight(.semibold)
                                            .padding(.horizontal)
                                            .padding(.vertical, 4)
                                            .frame(minWidth: totalWidth, alignment: .center)
                                            .background(.bar)
                                        columnHeaderRow
                                    }
                                }
                            }

                            if let attr = weatherService.attribution {
                                WeatherAttributionLink(info: attr)
                                    .padding()
                            }
                        }
                        .frame(minWidth: totalWidth)
                    }
                    .onScrollGeometryChange(for: ScrollEdges.self) { g in
                        let span = max(1, g.contentSize.height - g.containerSize.height)
                        let f = (g.contentOffset.y + g.contentInsets.top) / span
                        return ScrollEdges(
                            top: g.contentOffset.y <= g.contentInsets.top + 1,
                            bottom: g.contentOffset.y + g.containerSize.height
                                    >= g.contentSize.height - 1,
                            fraction: min(1, max(0, f)))
                    } action: { _, v in
                        atTop = v.top; atBottom = v.bottom
                        guard hasAligned else { return }
                        // Rows are hourly and evenly spaced, so scroll position
                        // maps almost linearly onto time — close enough to hand
                        // the graph the moment the user is looking at.
                        if let f = allRows.first?.date, let l = allRows.last?.date {
                            topDate = f.addingTimeInterval(v.fraction * l.timeIntervalSince(f))
                        }
                    }
                    // Only an over-scroll past an end switches screens, so normal
                    // scrolling through the rows is untouched.
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { v in
                                guard abs(v.translation.height) > abs(v.translation.width) else { return }
                                if v.translation.height < -70 && atBottom { onSwitchScreen?(1) }
                                else if v.translation.height > 70 && atTop { onSwitchScreen?(-1) }
                            }
                    )
                    .onDisappear { hasAligned = false }
                    // Line up with the graph every time the table is opened, not
                    // just the first time — SwiftUI keeps this view's state
                    // between visits, so a one-shot guard would only ever work
                    // once. Falls back to "now": with ten days of history above
                    // it, the top of the table is no longer where anyone wants
                    // to start.
                    .onAppear { alignToGraph(proxy) }
                    .onChange(of: weatherService.current?.id) { _, _ in alignToGraph(proxy) }
                }
            }
        }
    }

    // MARK: Column header row (two lines allowed)

    private var columnHeaderRow: some View {
        HStack(spacing: 0) {
            // MyFeels score column — unitless 0…1000 scale, no °F/°C suffix.
            headerCell("MyFeels\nLike", width: wMyFL, align: .center)
                .padding(.trailing, myFLTrailingGap)
            headerCell("Time",                                              width: wTime,  align: .leading)
            headerCell("",                                                  width: wSym,   align: .center)
            headerCell("UV",                                                width: wUV,    align: .trailing)
            headerCell("Temp /\nfeels " + (useFahrenheit ? "°F" : "°C"),    width: wTemp,  align: .trailing)
            headerCell("Wet\nbulb " + (useFahrenheit ? "°F" : "°C"),        width: wWet,   align: .trailing)
            headerCell("Dew\npt " + (useFahrenheit ? "°F" : "°C"),          width: wDew,   align: .trailing)
            headerCell("Wind (gust)\n" + (useFahrenheit ? "mph" : "kph"),   width: wWind,  align: .trailing)
            headerCell("Precip\n(%)",                                       width: wPrecip, align: .trailing)
            headerCell("Cloud\n(%)",                                        width: wCloud,  align: .trailing)
        }
        .font(.caption)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(.bar)
    }

    @ViewBuilder
    private func headerCell(_ text: String, width: CGFloat, align: Alignment) -> some View {
        Text(text)
            .fontWeight(.semibold)
            .multilineTextAlignment(textAlignment(for: align))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width, alignment: align)
    }

    private func textAlignment(for align: Alignment) -> TextAlignment {
        switch align {
        case .leading:  return .leading
        case .trailing: return .trailing
        default:        return .center
        }
    }

    // MARK: Data row

    private func dataRow(_ p: ForecastPoint) -> some View {
        HStack(spacing: 0) {
            myFeelsLikeCell(p)
                .padding(.trailing, myFLTrailingGap)

            cell(p.kind == .current ? "now" : timeLabel(for: p.date),
                 width: wTime, align: .leading,
                 color: p.kind == .current ? cMyFL : nil)

            // Weather condition icon
            Image(systemName: p.symbolName)
                .font(.caption)
                .frame(width: wSym, alignment: .center)

            cell(fmtUV(p.uvIndex),                                       width: wUV,    align: .trailing)
            cell(fmtTemp(p),                                             width: wTemp,  align: .trailing, color: cTemp)
            cell(fmt1(useFahrenheit ? p.wetBulbF    : p.wetBulbC),       width: wWet,   align: .trailing, color: cWet)
            cell(fmt1(useFahrenheit ? p.dewPointF   : p.dewPointC),      width: wDew,   align: .trailing, color: cDew)
            cell(fmtWind(p),                                             width: wWind,  align: .trailing, color: cWind)
            // CurrentWeather has no precipitation or cloud-by-altitude breakdown.
            cell(p.kind == .current ? "" : fmtPrecip(p), width: wPrecip, align: .trailing, color: cPrecip)
            cell(fmtCloud(p),   width: wCloud,  align: .trailing)
        }
        .font(.caption)
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
    }

    // MyFeels score cell — colored background, 3-digit number with text color
    // chosen for contrast. Empty dash when no model has been fitted yet.
    @ViewBuilder
    private func myFeelsLikeCell(_ p: ForecastPoint) -> some View {
        if let score = p.myFeelsLikeScore {
            let clamped = max(ColorScale.minScore, min(ColorScale.maxScore, score))
            Text(String(format: "%.0f", clamped))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(ColorScale.contrastingText(forScore: clamped))
                .frame(width: wMyFL, alignment: .center)
                .padding(.vertical, 2)
                .background(ColorScale.color(forScore: clamped))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Text("—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: wMyFL, alignment: .center)
        }
    }

    // MARK: Formatting helpers

    private func fmt1(_ n: Double) -> String { String(format: "%.1f", n) }
    private func fmtUV(_ n: Double) -> String { String(format: "%d", Int(n)) }

    private func fmtTemp(_ p: ForecastPoint) -> String {
        useFahrenheit
            ? String(format: "%.1f (%.1f)", p.temperatureF, p.apparentTemperatureF)
            : String(format: "%.1f (%.1f)", p.temperatureC, p.apparentTemperatureC)
    }

    private func fmtWind(_ p: ForecastPoint) -> String {
        let s = useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH
        let g = useFahrenheit ? p.windGustMPH  : p.windGustKPH
        return String(format: "%.0f (%.0f)", s, g)
    }

    private func fmtPrecip(_ p: ForecastPoint) -> String {
        String(format: "%.1f (%.0f%%)", p.precipitationMM, p.precipProbability * 100)
    }

    private func fmtCloud(_ p: ForecastPoint) -> String {
        // "now" has total cloud only — no by-altitude breakdown.
        if p.kind == .current {
            return String(format: "%.0f", p.cloudCover * 100)
        }
        return String(format: "%.0f (l:%.0f m:%.0f h:%.0f)",
                      p.cloudCover * 100,
                      p.cloudCoverLow * 100,
                      p.cloudCoverMedium * 100,
                      p.cloudCoverHigh * 100)
    }

    // MARK: Layout helpers

    @ViewBuilder
    private func cell(
        _ text: String,
        width: CGFloat,
        align: Alignment,
        color: Color? = nil
    ) -> some View {
        Text(text)
            .foregroundStyle(color ?? .primary)
            .frame(width: width, alignment: align)
            .lineLimit(1)
    }

    // Subtle alternating row tint; the "now" row gets extra emphasis.
    private func rowBackground(_ p: ForecastPoint) -> Color {
        if p.kind == .current { return Color.accentColor.opacity(0.12) }
        let idx = allRows.firstIndex(where: { $0.id == p.id }) ?? 0
        return idx.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.03)
    }
}

#Preview {
    ForecastTableView(weatherService: WeatherService(), nowTick: .now,
                      topDate: .constant(nil))
}
