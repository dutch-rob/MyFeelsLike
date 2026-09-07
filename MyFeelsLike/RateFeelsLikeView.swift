// SPDX-License-Identifier: GPL-3.0-or-later
//
//  RateFeelsLikeView.swift
//  MyFeelsLike
//
//  Sheet for the user to record one "feels like" rating, expressed purely as
//  a position on a color scale — no temperature units are shown.
//
//  Layout
//  ──────
//    LEFT  — A wide color column that is taller than the visible viewport
//            (at most half of it fits on screen). The user scrolls the
//            column up/down; a fixed horizontal indicator sits across the
//            middle of the visible area, with small triangles overhanging
//            the left and right edges and pointing inward. The color
//            under the indicator is the rating.
//    RIGHT — The "How does it feel right now?" prompt and the categorical
//            questions (Activity / Dressed / Sun, where sun is hidden
//            after sunset).
//
//  The rating is stored as a Double in [0, 1000] (feelsLikeScore on Rating).
//  This score is the regression model's target variable and has no
//  temperature units — color is interpreted directly by the user.
//

import SwiftUI
import SwiftData

struct RateFeelsLikeView: View {
    @AppStorage(SettingsKey.colorVisionMode)
    private var visionMode = ColorScale.ColorVisionMode.full
    @AppStorage(SettingsKey.noColorStyle)
    private var noColorStyle = ColorScale.NoColorStyle.lineGraph

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Current weather sample to attach to this rating.
    let snapshot: ForecastPoint
    /// Place this rating belongs to (nil if user is on "current location").
    let placeID: UUID?
    /// Kept on the API for source compatibility but no longer used in the UI.
    let useFahrenheit: Bool

    // User selections. The categorical answers start unset (nil): people
    // easily forget to review a pre-selected default, so Save stays disabled
    // until each has been chosen deliberately.
    @State private var feelsLikeScore: Double = 500   // middle of [0, 1000]
    @State private var activity: Int? = nil
    @State private var dress: Int? = nil
    @State private var sun: Int? = nil

    /// Identifies which option's hint popover is currently open (if any).
    @State private var shownHint: HintID? = nil

    init(snapshot: ForecastPoint,
         placeID: UUID?,
         useFahrenheit: Bool) {
        self.snapshot = snapshot
        self.placeID = placeID
        self.useFahrenheit = useFahrenheit
        // After sunset there is no meaningful sun/shade distinction, so shade
        // is assumed and counts as answered; daylight requires a choice.
        _sun = State(initialValue: snapshot.isDaylight ? nil : -1)
    }

    /// True once every categorical question has an explicit answer.
    private var allAnswered: Bool {
        activity != nil && dress != nil && sun != nil
    }

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 0) {
                // ── LEFT: scrollable color column ────────────────────────
                ColorScoreColumn(score: $feelsLikeScore)
                    .frame(width: 150)
                    .padding(.leading, 16)
                    .padding(.trailing, 16)
                    .padding(.vertical, 12)

                // ── EXPERIMENT: the same score on a picker wheel ──────────
                // Temporary, sitting beside the column so the two instruments
                // can be tried against each other on the same rating. Both
                // drive `feelsLikeScore`, so moving either moves the other.
                // This pushes the questionnaire off-screen; that is expected
                // while the comparison is up.
                ColorScoreWheel(score: $feelsLikeScore)
                    .frame(width: 120)
                    .padding(.trailing, 16)
                    .padding(.vertical, 12)

                // ── RIGHT: questions ──────────────────────────────────────
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        promptHeader
                        questionnaire
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Rate Feels Like")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.bold().disabled(!allAnswered)
                }
            }
        }
    }

    // MARK: Prompt + questionnaire

    private var promptHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("How does it feel right now?")
                .font(.headline)
            Text(visionMode == .noColor
                 ? "Scroll the column until the strip across the middle sits at how this weather feels to you."
                 : "Scroll the color column until the strip across the middle shows the color that matches how this weather feels to you.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            // In No color mode the column carries names rather than a hue, so
            // show the reading itself: the category, and the number that is
            // actually recorded and modelled.
            if visionMode == .noColor {
                HStack(spacing: 6) {
                    Text(ColorScale.categoryName(forScore: feelsLikeScore))
                        .font(.title3.weight(.semibold))
                    Text("\(Int(feelsLikeScore.rounded()))")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Selected: \(ColorScale.categoryName(forScore: feelsLikeScore)), \(Int(feelsLikeScore.rounded())) out of 1000")
            }
        }
    }

    private var questionnaire: some View {
        VStack(alignment: .leading, spacing: 14) {
            categoricalPicker(
                title: "Activity",
                value: $activity,
                options: [
                    (0, "Not active",  "Sitting, standing still, lying down."),
                    (1, "Light",       "Slow walking, cooking, light chores. You can talk and sing."),
                    (2, "Moderate",    "Brisk walking, water aerobics, doubles tennis. You can talk, but not sing."),
                    (3, "Vigorous",    "Running, swimming fast, heavy lifting. You cannot say more than a few words.")
                ]
            )
            categoricalPicker(
                title: "Dressed for",
                value: $dress,
                options: [
                    (-2, "very cold", nil),
                    (-1, "cold",      nil),
                    ( 0, "nice",      nil),
                    ( 1, "warm",      nil),
                    ( 2, "very warm", nil)
                ]
            )
            if snapshot.isDaylight {
                categoricalPicker(
                    title: "Sun / shade",
                    value: $sun,
                    options: [
                        ( 1, "In full sun",      nil),
                        ( 0, "Partially shaded", nil),
                        (-1, "In shade",         nil)
                    ]
                )
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sun / shade").font(.subheadline.weight(.semibold))
                    Text("After sunset, shade is assumed.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func categoricalPicker(
        title: String,
        value: Binding<Int?>,
        options: [(Int, String, String?)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(options, id: \.0) { (raw, label, hint) in
                HStack(alignment: .center, spacing: 8) {
                    Button {
                        value.wrappedValue = raw
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: value.wrappedValue == raw ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(value.wrappedValue == raw ? Color.accentColor : .secondary)
                            Text(label).font(.callout)
                        }
                    }
                    .buttonStyle(.plain)

                    if let hint {
                        let id = HintID(category: title, value: raw)
                        Button {
                            shownHint = (shownHint == id) ? nil : id
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(
                            isPresented: Binding(
                                get: { shownHint == id },
                                set: { if !$0 { shownHint = nil } }
                            ),
                            arrowEdge: .top
                        ) {
                            Text(hint)
                                .font(.callout)
                                .padding(12)
                                .frame(maxWidth: 260)
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Save

    private func save() {
        guard let activity, let dress, let sun else { return }
        let rating = Rating(
            placeID: placeID,
            feelsLikeScore: feelsLikeScore,
            activity: activity,
            dress: dress,
            sun: sun,
            snapshot: snapshot
        )
        modelContext.insert(rating)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Helpers

private struct HintID: Hashable {
    let category: String
    let value: Int
}

// MARK: - ColorScoreColumn
//
// A vertically scrollable color column. The column's content is twice as
// tall as the visible viewport (so at most half fits on screen at once).
// A fixed horizontal indicator sits at the vertical center of the viewport
// — as the user scrolls, the color passing under the indicator becomes
// the selected score.
//
// The color gradient is constructed so the indicator can sweep the full
// 0…1000 score range from one scroll extreme to the other: the middle half
// of the content height carries the anchor colors evenly distributed,
// padded with solid "hot" above and solid "cold" below.

struct ColorScoreColumn: View {
    @Binding var score: Double   // 0…1000
    @AppStorage(SettingsKey.colorVisionMode)
    private var visionMode = ColorScale.ColorVisionMode.full
    @AppStorage(SettingsKey.noColorStyle)
    private var noColorStyle = ColorScale.NoColorStyle.lineGraph

    var body: some View {
        GeometryReader { geo in
            let h = max(1, geo.size.height)
            let contentHeight = h * 3.0     // 2h scroll range → factor-2 stretch vs original
            let usableRange = contentHeight - h
            let indicatorOverhang: CGFloat = 12

            ZStack(alignment: .topLeading) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        // A VStack with a tiny invisible anchor ("mid") placed at
                        // exactly the content midpoint. ScrollViewReader scrolls to
                        // it on appear so score 500 starts under the indicator.
                        VStack(spacing: 0) {
                            Color.clear.frame(height: contentHeight / 2 - 0.5)
                            Color.clear.frame(height: 1).id("mid")
                            Color.clear.frame(height: contentHeight / 2 - 0.5)
                        }
                        .frame(height: contentHeight)
                        .background(
                            Group {
                                if visionMode == .noColor, noColorStyle == .lineGraph {
                                    // Same geometry as the ruler overlay below, so
                                    // the categories line up with the tick marks.
                                    ComfortCategoryLadder(activeTop: h / 2, activeSpan: 2 * h)
                                } else {
                                    LinearGradient(gradient: Self.paddedScoreGradient(),
                                                   startPoint: .top, endPoint: .bottom)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        )
                        // Ruler gradation down the middle — no numbers. A tick
                        // every 10 score gives a fine ruler feel; longer major
                        // ticks every 50 with four minor ticks between. All black,
                        // which reads on both palettes.
                        .overlay(
                            Canvas { ctx, size in
                                let activeTop = h / 2, activeSpan = 2 * h
                                let cx = size.width / 2
                                let thickness: CGFloat = 1.25
                                for s in stride(from: 0, through: 1000, by: 10) {
                                    let y = activeTop + activeSpan * (1 - CGFloat(s) / 1000)
                                    let len: CGFloat = (s % 50 == 0) ? 15 : 8
                                    ctx.fill(Path(CGRect(x: cx - len, y: y - thickness / 2,
                                                         width: 2 * len, height: thickness)),
                                             with: .color(tickColor))
                                }
                            }
                            .allowsHitTesting(false)
                        )
                    }
                    .frame(height: h)
                    // Read the actual scroll offset directly. The previous
                    // GeometryReader/preference approach could get stuck reading
                    // the top of the column, recording 1000 on every rating.
                    .onScrollGeometryChange(for: CGFloat.self) { geoProxy in
                        geoProxy.contentOffset.y
                    } action: { _, offsetY in
                        guard let s = Self.score(forOffsetY: offsetY, usableRange: usableRange) else { return }
                        if abs(s - score) > 0.5 { score = s }
                    }
                    .onAppear {
                        // Defer one runloop tick so layout has finished.
                        DispatchQueue.main.async {
                            proxy.scrollTo("mid", anchor: .center)
                        }
                    }
                }

                // Indicator overlay — wider than the column so the triangles
                // overhang to the left and right.
                IndicatorOverlay()
                    .frame(width: geo.size.width + 2 * indicatorOverhang, height: 16)
                    .position(x: geo.size.width / 2, y: h / 2)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Ruler ink. Black reads on every color of the gradient; the No color
    /// ladder is a system background that follows light/dark, so there the
    /// ticks follow the text color instead.
    private var tickColor: Color {
        visionMode == .noColor && noColorStyle == .lineGraph ? .primary : .black
    }

    /// Maps a scroll content offset to a score in 0…1000. `offsetY == 0`
    /// (top, unscrolled) → 1000 (hot); `offsetY == usableRange` (fully
    /// scrolled down) → 0 (cold); values outside that span are clamped.
    /// Returns `nil` for a degenerate (zero or negative) usable range,
    /// matching the guard in the live scroll-geometry callback above.
    ///
    /// This is the exact computation that regressed once before: a stuck
    /// GeometryReader/preference read meant `offsetY` never changed, so
    /// every rating silently recorded 1000 regardless of scroll position.
    static func score(forOffsetY offsetY: CGFloat, usableRange: CGFloat) -> Double? {
        guard usableRange > 0 else { return nil }
        let frac = offsetY / usableRange
        return (1.0 - max(0, min(1, frac))) * 1000.0
    }

    /// Builds the gradient for a contentHeight = h * 3.0 column.
    ///
    /// padFrac = (h/2) / (3h) = 1/6: the top and bottom 1/6 of the content
    /// are non-selectable (indicator cannot reach there) and are rendered
    /// fully transparent. The middle 2/3 carries the active color range.
    /// Hard cut at each boundary (epsilon step) avoids a color bleed.
    ///
    /// A power curve (exponent 0.6) is applied so that dark color transitions
    /// (black → purple near the top) get proportionally more visible space.
    /// `legacy` builds the previous palette instead, so testers can compare the
    /// two side by side on the rating column.
    static func paddedScoreGradient(legacy: Bool = false) -> Gradient {
        let padFrac: Double = 1.0 / 6.0          // (h/2) / (3h)
        let activeRange = 1.0 - 2.0 * padFrac    // 2/3
        let eps: Double = 0.0005

        // Score 1000 sits at the top of the active area, 0 at the bottom.
        // Sampling the shared color function keeps the column and the forecast
        // colors identical by construction.
        var stops: [Gradient.Stop] = [
            .init(color: .clear, location: 0.0),
            .init(color: .clear, location: padFrac - eps)
        ]
        let steps = 48
        for i in 0...steps {
            let f = Double(i) / Double(steps)                 // 0 = top = hottest
            let score = ColorScale.maxScore * (1 - f)
            let c = legacy ? ColorScale.legacyColor(forScore: score)
                           : ColorScale.color(forScore: score)
            stops.append(.init(color: c, location: padFrac + activeRange * f))
        }
        let cold = legacy ? ColorScale.legacyColor(forScore: 0) : ColorScale.color(forScore: 0)
        stops.append(.init(color: cold, location: 1.0 - padFrac + eps))
        stops.append(.init(color: .clear, location: 1.0 - padFrac + 2 * eps))
        stops.append(.init(color: .clear, location: 1.0))
        return Gradient(stops: stops)
    }
}

// MARK: - Picker-wheel scale (experiment)

/// EXPERIMENTAL alternative to `ColorScoreColumn`: the same 0…1000 comfort
/// score on a picker wheel instead of a sliding bar.
///
/// Rows every 10 points, matching the fine ticks on the column's ruler, and hot
/// at the top so the wheel runs the same way round as the gradient. A wheel of
/// bare colour would have nothing to aim at, so the row nearest each category
/// anchor carries its name — the same six landmarks the no-colour ladder uses.
struct ColorScoreWheel: View {
    @Binding var score: Double   // 0…1000

    @AppStorage(SettingsKey.colorVisionMode)
    private var visionMode = ColorScale.ColorVisionMode.full
    @AppStorage(SettingsKey.noColorStyle)
    private var noColorStyle = ColorScale.NoColorStyle.lineGraph

    /// A wheel shows about seven rows at once, so the step decides how much of
    /// the scale is visible. At the column's 10-point tick spacing that is 60
    /// points out of 1000 — seven near-identical greens, telling you nothing
    /// about where you are. 25 puts roughly 150 points on screen, enough for the
    /// colour to move under your thumb, and still finer than anyone rates to.
    private static let stepSize = 25
    /// Hot first: the wheel reads top-to-bottom like the column's gradient.
    private static let steps: [Int] =
        Array(stride(from: Int(ColorScale.maxScore), through: Int(ColorScale.minScore),
                     by: -stepSize))

    /// Rows that sit closest to a category anchor, which are the ones labelled.
    private static let landmarks: [Int: String] = {
        var m: [Int: String] = [:]
        for c in ColorScale.comfortCategories {
            let row = Int((c.score / Double(stepSize)).rounded()) * stepSize
            m[row] = c.name
        }
        return m
    }()

    /// The wheel works in whole steps; the score it drives is continuous.
    private var selection: Binding<Int> {
        Binding(get: { Int((score / Double(Self.stepSize)).rounded()) * Self.stepSize },
                set: { score = Double($0) })
    }

    /// True when colour carries nothing and the names have to do the work.
    private var namesOnly: Bool { visionMode == .noColor }

    var body: some View {
        Picker("Comfort score", selection: selection) {
            ForEach(Self.steps, id: \.self) { s in
                row(for: s).tag(s)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .accessibilityLabel("Comfort scale from hot at the top to very cold at the bottom")
    }

    @ViewBuilder
    private func row(for s: Int) -> some View {
        let name = Self.landmarks[s]
        if namesOnly {
            // No colour to read, so every row says where it is: the landmark
            // name where there is one, a tick elsewhere.
            Text(name ?? "·")
                .font(name == nil ? .caption2 : .callout)
                .foregroundStyle(name == nil ? .secondary : .primary)
        } else {
            // Full-bleed and as tall as the row allows: the wheel style fades
            // and shrinks everything but the selected row, so the colour needs
            // all the area it can get to survive that.
            ZStack {
                Rectangle()
                    .fill(ColorScale.color(forScore: Double(s)))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                if let name {
                    Text(name)
                        .font(.caption).fontWeight(.semibold)
                        // Outlined the way the band labels are, because the row
                        // colour underneath runs from deep blue to red.
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 1)
                        .shadow(color: .black, radius: 1)
                }
            }
        }
    }
}

// MARK: - Indicator overlay

/// A thin white horizontal bar with small white triangles overhanging the
/// column edges on the left and right, both pointing inward. The bar sits
/// inside the column area; the triangles stick out by 12 pt on each side.
private struct IndicatorOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let triangleW: CGFloat = 12
            let cy = geo.size.height / 2
            let halfH: CGFloat = 6

            ZStack {
                // Thin horizontal bar covering only the column area (not the
                // overhang where the triangles live).
                Path { p in
                    p.move(to: CGPoint(x: triangleW, y: cy))
                    p.addLine(to: CGPoint(x: w - triangleW, y: cy))
                }
                .stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .square))

                // Left triangle (apex right — points into the column)
                Path { p in
                    p.move(to: CGPoint(x: 0,         y: cy - halfH))
                    p.addLine(to: CGPoint(x: triangleW, y: cy))
                    p.addLine(to: CGPoint(x: 0,         y: cy + halfH))
                    p.closeSubpath()
                }
                .fill(.white)

                // Right triangle (apex left — points into the column)
                Path { p in
                    p.move(to: CGPoint(x: w,             y: cy - halfH))
                    p.addLine(to: CGPoint(x: w - triangleW, y: cy))
                    p.addLine(to: CGPoint(x: w,             y: cy + halfH))
                    p.closeSubpath()
                }
                .fill(.white)
            }
            .shadow(color: .black.opacity(0.35), radius: 1.2)
        }
    }
}
