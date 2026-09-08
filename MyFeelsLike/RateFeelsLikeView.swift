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

// MARK: - Color wheel scale (experiment)

/// EXPERIMENTAL alternative to `ColorScoreColumn`: the same 0…1000 comfort score
/// on a wheel we draw ourselves.
///
/// `.pickerStyle(.wheel)` was tried first and fails this job twice over. It fades
/// and shrinks every row but the selected one, which is precisely what a colour
/// ramp cannot survive, and it quantises to discrete rows — at a spacing coarse
/// enough to show any colour range at all, far too coarse to rate with.
///
/// Drawing it ourselves fixes both, and buys range as a bonus. The wheel is a
/// cylinder seen edge-on: a point at angle θ from the centre sits at sin(θ), so
/// the scale compresses toward the rim exactly as a real wheel does. Pick the
/// scale-per-radian so a half turn is the whole scale and **all 1000 points are
/// on screen at once**, magnified where you are looking and squeezed at the
/// edges — more range than the column shows uniformly, and far more than the
/// Picker's ~150. Colour is sampled per scanline at full saturation: nothing
/// fades, and the score is a Double throughout, so there is nothing to snap to.
struct ColorScoreWheel: View {
    @Binding var score: Double   // 0…1000

    @AppStorage(SettingsKey.colorVisionMode)
    private var visionMode = ColorScale.ColorVisionMode.full

    /// Where the drag started, so a drag is absolute rather than incremental.
    @State private var dragBase: Double? = nil

    /// Scale units per radian of turn. A half turn (π) is the full scale, which
    /// is what puts every point on the wheel at once.
    private static let scorePerRadian = ColorScale.maxScore / .pi

    /// Height of one drawn band. 1.5 pt is below the point at which banding
    /// shows on the gradient and keeps the per-frame fill count in the
    /// hundreds — a screen-height wheel is under 300 fills.
    private static let bandHeight: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            let h = max(1, geo.size.height)
            let radius = h / 2
            // Scale units per point of finger travel, at the centre where the
            // wheel is least compressed. Elsewhere the surface moves faster,
            // but tracking the touch point exactly makes the far edges
            // uncontrollable; the centre rate is what the thumb expects.
            let rate = Self.scorePerRadian / Double(radius)

            ZStack(alignment: .topLeading) {
                wheelCanvas
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                if dragBase == nil { dragBase = score }
                                score = Self.clampScore(
                                    (dragBase ?? score) + Double(v.translation.height) * rate)
                            }
                            .onEnded { v in
                                // Carry the flick on rather than stopping dead
                                // under the finger.
                                let projected = Self.clampScore(
                                    (dragBase ?? score)
                                    + Double(v.predictedEndTranslation.height) * rate)
                                dragBase = nil
                                withAnimation(.easeOut(duration: 0.35)) { score = projected }
                            }
                    )

                // The same indicator the column uses, so the two instruments are
                // read the same way.
                IndicatorOverlay()
                    .frame(width: geo.size.width + 24, height: 16)
                    .position(x: geo.size.width / 2, y: radius)
                    .allowsHitTesting(false)
            }
            .accessibilityElement()
            .accessibilityLabel("Comfort scale wheel")
            .accessibilityValue(ColorScale.categoryName(forScore: score))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: score = Self.clampScore(score + 25)
                case .decrement: score = Self.clampScore(score - 25)
                default: break
                }
            }
        }
    }

    private static func clampScore(_ s: Double) -> Double {
        min(ColorScale.maxScore, max(ColorScale.minScore, s))
    }

    /// Screen y for a score, or nil when it has turned past the rim.
    private static func y(forScore s: Double, centre: Double, radius: CGFloat) -> CGFloat? {
        let theta = (centre - s) / scorePerRadian
        guard abs(theta) <= .pi / 2 else { return nil }
        return radius + radius * CGFloat(sin(theta))
    }

    private var wheelCanvas: some View {
        Canvas { ctx, size in
            let radius = max(1, size.height / 2)

            // The surface: one fill per band, colour sampled at that band's
            // angle. Full saturation everywhere — the fade is the whole reason
            // the system picker was no good here.
            var y: CGFloat = 0
            while y < size.height {
                let dy = (y + Self.bandHeight / 2) - radius
                let t = max(-1, min(1, Double(dy / radius)))
                let s = score - Self.scorePerRadian * asin(t)
                ctx.fill(
                    Path(CGRect(x: 0, y: y, width: size.width,
                                height: Self.bandHeight + 0.6)),
                    with: .color(ColorScale.color(forScore: s)))
                y += Self.bandHeight
            }

            // Ticks every 50, bunching toward the rim because they are spaced
            // by angle. This is what reads as curvature, and it does so without
            // touching the colours.
            let cx = size.width / 2
            for tick in stride(from: 0.0, through: ColorScale.maxScore, by: 50) {
                guard let ty = Self.y(forScore: tick, centre: score, radius: radius)
                else { continue }
                let major = tick.truncatingRemainder(dividingBy: 250) == 0
                let len: CGFloat = major ? 14 : 7
                ctx.fill(Path(CGRect(x: cx - len, y: ty - 0.6,
                                     width: 2 * len, height: 1.25)),
                         with: .color(.black.opacity(0.55)))
            }

            // Category names, so there is something to aim at. Nearest the
            // selection first, and a name is dropped if it would collide with
            // one already placed: toward the rim the compression stacks the
            // anchors within a few points of each other, and two overlapping
            // labels name neither position.
            var placed: [CGFloat] = []
            let byNearest = ColorScale.comfortCategories
                .sorted { abs($0.score - score) < abs($1.score - score) }
            for c in byNearest {
                guard let ty = Self.y(forScore: c.score, centre: score, radius: radius)
                else { continue }
                var text = ctx.resolve(
                    Text(c.name)
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundStyle(.white))
                text.shading = .color(.white)
                let sz = text.measure(in: size)
                // Keep the name inside the wheel as it nears the rim.
                let clampedY = min(max(ty, sz.height / 2 + 2),
                                   size.height - sz.height / 2 - 2)
                guard placed.allSatisfy({ abs($0 - clampedY) >= sz.height + 3 })
                else { continue }
                placed.append(clampedY)
                // A dark plate behind it: the ramp runs from deep blue to red,
                // so neither a light nor a dark name works everywhere.
                ctx.fill(
                    Path(roundedRect: CGRect(x: cx - sz.width / 2 - 4,
                                             y: clampedY - sz.height / 2 - 1,
                                             width: sz.width + 8,
                                             height: sz.height + 2),
                         cornerRadius: 3),
                    with: .color(.black.opacity(0.45)))
                ctx.draw(text, at: CGPoint(x: cx, y: clampedY))
            }
        }
        .drawingGroup()
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
