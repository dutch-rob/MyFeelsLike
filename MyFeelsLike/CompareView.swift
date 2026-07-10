// SPDX-License-Identifier: GPL-3.0-or-later
//
//  CompareView.swift
//  MyFeelsLike
//
//  Phase 1 scaffold of the "Compare with:" screen: the entry points for
//  linking with other users (nearby / via text) plus the user's own
//  MyFeelsLike color band. The networking (live nearby link, text invite,
//  peer model exchange) lands in later phases — for now the two buttons are
//  placeholders and only the user's own band is shown.
//

import SwiftUI
import Charts

// MARK: - Bottom-bar icon

/// Compare icon for the bottom bar: two people over a two-tone MyFeelsLike bar
/// (green-yellow vs yellow-orange) — "compare your colors with someone".
/// The people follow the bar tint; the color swatch keeps its own colors.
struct CompareIcon: View {
    var body: some View {
        // Colors flank the figures (rather than sitting under them) so the icon
        // is wider, the people can be taller, and the whole thing reads clearly.
        HStack(spacing: 3) {
            swatch(ColorScale.color(forScore: 300))   // green-yellow
            Image(systemName: "person.2.fill")
                .font(.system(size: 17))
            swatch(ColorScale.color(forScore: 420))   // yellow-orange
        }
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: 5, height: 18)
    }
}

// MARK: - Color band + row

/// A thin horizontal MyFeelsLike color band over a 24h series (one cell per
/// hour). Gray placeholder when there's no personalized model yet.
struct FeelsBand: View {
    let series: [ForecastPoint]

    private var domain: ClosedRange<Date>? {
        guard let f = series.first?.date, let l = series.last?.date, f < l else { return nil }
        return f...l
    }
    private var hasColor: Bool { series.contains { $0.myFeelsLikeScore != nil } }

    var body: some View {
        Group {
            if let domain, hasColor {
                Chart(series) { p in
                    RectangleMark(
                        xStart: .value("t0", p.date.addingTimeInterval(-3600)),
                        xEnd:   .value("t1", p.date),
                        yStart: .value("y0", 0), yEnd: .value("y1", 1))
                    .foregroundStyle(color(p))
                }
                .chartYScale(domain: 0...1)
                .chartYAxis(.hidden)
                .chartXAxis(.hidden)
                .chartXScale(domain: domain)
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.2))
                    .overlay(Text("No color yet").font(.caption2).foregroundStyle(.secondary))
            }
        }
        .frame(height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func color(_ p: ForecastPoint) -> Color {
        ColorScale.feelsColor(score: p.myFeelsLikeScore, opacity: p.myFeelsLikeOpacity)
    }
}

/// One labeled color band in the compare list (a user's name + their band).
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
    @ObservedObject var nearby: NearbyCompareManager
    /// The phone user's own personalized 24h series (their color band).
    let ownSeries: [ForecastPoint]
    /// Builds a color-band series by applying a peer's model to *our* local
    /// forecast, so every band compares the same weather.
    let bandSeries: (RegressionState?) -> [ForecastPoint]
    /// Legible text color over the weather-sky background.
    var ink: Color = .primary

    @State private var showComingSoon = false

    @AppStorage(SettingsKey.compareName) private var compareName = ""
    @AppStorage(SettingsKey.didAskCompareName) private var didAskCompareName = false
    @State private var showNamePrompt = false
    @State private var nameDraft = ""

    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Compare with:")
                    .font(.headline).foregroundStyle(ink)

                HStack(spacing: 12) {
                    Button {
                        nearby.isBrowsing ? nearby.stopBrowsing() : nearby.startBrowsing()
                    } label: {
                        chip(nearby.isBrowsing ? "Searching…" : "Connect Nearby",
                             systemImage: "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(.plain)
                    .disabled(nearby.atCapacity && !nearby.isBrowsing)

                    Button { showComingSoon = true } label: {
                        chip("Invite via Text", systemImage: "message")
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }

                // You're discoverable just by being here — only the person
                // starting the link has to search.
                Text("Others can invite you while this screen is open.")
                    .font(.caption2).foregroundStyle(ink.opacity(0.7))

                if nearby.isBrowsing { discoverySection }

                Divider()

                // Every band is your local weather run through that person's
                // model, so they compare like-for-like.
                Text("Same weather, each person's model")
                    .font(.caption).foregroundStyle(ink.opacity(0.75))

                // Own band first, then each connected peer's. All bands are the
                // same width so they line up for comparison (a link ends when
                // the app closes, so no per-row cancel is needed — see "End all").
                CompareBandRow(name: "You", series: ownSeries, ink: ink)
                ForEach(nearby.peers) { peer in
                    CompareBandRow(name: peerLabel(peer), series: bandSeries(peer.model), ink: ink)
                }

                if !nearby.peers.isEmpty {
                    Button(role: .destructive) { nearby.cancelAll() } label: {
                        Label("End all links", systemImage: "xmark.circle")
                    }
                    .font(.footnote)
                    .padding(.top, 4)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Incoming invitation: accept for 1 hour / until cancel, or decline.
        .confirmationDialog("Compare with \(nearby.pendingInvite?.name ?? "")?",
                            isPresented: pendingInviteBinding,
                            titleVisibility: .visible,
                            presenting: nearby.pendingInvite) { invite in
            Button("Accept · for 1 hour") { nearby.accept(invite, lifetime: .oneHour) }
            Button("Accept · until one of us cancels") { nearby.accept(invite, lifetime: .untilCancel) }
            Button("Decline", role: .cancel) { nearby.decline(invite) }
        } message: { _ in
            Text("A nearby link also ends when either app is closed.")
        }
        // First use: ask what name others should see (iOS hides the real device
        // name from apps, so everyone would otherwise show up as "iPhone").
        .alert("Your compare name", isPresented: $showNamePrompt) {
            TextField("Name", text: $nameDraft)
            Button("Save") {
                let n = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty { compareName = n }
                didAskCompareName = true
                nearby.refreshIdentity()
            }
            Button("Not now", role: .cancel) { didAskCompareName = true }
        } message: {
            Text("This is what other people see when you compare nearby. You can change it later in Settings.")
        }
        .alert("Coming soon", isPresented: $showComingSoon) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Inviting by text is being built. For now, use Connect Nearby.")
        }
        .onAppear {
            nearby.startAdvertising()          // discoverable while this screen is open
            if !didAskCompareName,
               compareName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showNamePrompt = true
            }
        }
        .onDisappear {                          // keep live links, stop radio work
            nearby.stopBrowsing()
            nearby.stopAdvertising()
        }
    }

    /// Styled like the scenario chips on the forecast screens: a frosted capsule
    /// with a hairline edge, so it reads over the weather-sky background.
    @ViewBuilder
    private func chip(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.caption2)
            Text(title).font(.caption.weight(.medium))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5))
    }

    // MARK: Discovery list

    @ViewBuilder
    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if nearby.discovered.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Searching for nearby users…")
                        .font(.footnote).foregroundStyle(ink)
                }
            } else {
                ForEach(nearby.discovered) { d in
                    Button { nearby.invite(d) } label: {
                        Label(d.name, systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .font(.footnote)
                    .disabled(nearby.atCapacity)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var pendingInviteBinding: Binding<Bool> {
        Binding(get: { nearby.pendingInvite != nil },
                set: { if !$0, let inv = nearby.pendingInvite { nearby.decline(inv) } })
    }

    private func peerLabel(_ peer: NearbyCompareManager.Peer) -> String {
        if let d = peer.deadline {
            return "\(peer.name) · ends \(Self.clock.string(from: d))"
        }
        return "\(peer.name) · until cancel"
    }
}
