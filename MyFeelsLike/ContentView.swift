// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import Charts
import CoreLocation
import Combine
import SwiftData

// ForecastPoint now lives in ForecastPoint.swift (shared with the watch app).

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var locationProvider = LocationProvider()
    @StateObject private var weather = WeatherService()
    @StateObject private var places = PlacesViewModel()
    @StateObject private var nearby = NearbyCompareManager()
    @State private var selectedPlace: Place? = nil
    @State private var nowTick: Date = .now
    /// Drives "now"-dependent UI (the loading "(working…)" hints and the
    /// day/night sky switch). Fires every second, but `nowTick` is only
    /// refreshed once a minute when idle (see the onReceive below) so the whole
    /// view tree isn't re-evaluated twice a second for nothing.
    private let progressTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var showPlaces   = false
    @State private var showRate     = false
    @State private var showSettings = false
    /// When true, the Compare screen replaces the forecast content (the bottom
    /// bar swaps its compare button for a back button).
    @State private var showingCompare = false
    /// Set when a compare invite deep link is opened; passed into CompareView.
    @State private var incomingInvite: CompareInvite? = nil
    @State private var showInfo    = false
    @State private var showWelcome = false
    /// Set when the welcome sheet's "Read the guide" was tapped; opens Info once
    /// that sheet has finished dismissing (sheets can't overlap).
    @State private var wantsGuide  = false
    @AppStorage(SettingsKey.lastSeenVersion) private var lastSeenVersion = ""
    // Tab indices: 0 = table phantom, 1 = 24h (real), 2 = 10d (real),
    //              3 = table (real), 4 = 24h phantom  — for circular wrap.
    /// Which screen the paged mode is showing (the vertical swipe walks these).
    @State private var screen: ForecastScreen = .today
    /// Left edge of the visible window, as an offset from "now". Shared by both
    /// graph screens, so panning survives a screen switch.
    @State private var startOffset: TimeInterval = 0
    @State private var panBase: TimeInterval? = nil
    /// Locked once a drag has clearly chosen an axis, so a diagonal swipe
    /// doesn't both pan and switch screens.
    @State private var dragAxis: DragAxis? = nil
    /// How far the screen has been dragged vertically, so the screens move with
    /// the finger instead of jumping at the end of the gesture.
    @State private var dragY: CGFloat = 0
    /// With the zoom graph on, whether the table is showing instead.
    @State private var zoomShowsTable = false
    /// The moment showing at the top of the table, so switching between the
    /// table and a graph keeps the same place in time.
    @State private var tableTopDate: Date? = nil
    /// Which graph to come back to from the table.
    @State private var lastGraph: ForecastScreen = .today

    private enum DragAxis { case horizontal, vertical }
    @AppStorage(SettingsKey.useFahrenheit) private var useFahrenheit: Bool = true
    @AppStorage(DeveloperDataSync.consentKey) private var shareData: Bool = false
    @AppStorage(SettingsKey.scenarioActivity) private var scenarioActivity: Int = 1
    @AppStorage(SettingsKey.scenarioDress)    private var scenarioDress:    Int = 0
    @AppStorage(SettingsKey.scenarioSun)      private var scenarioSun:      Int = 0
    @AppStorage(GraphKey.temp)     private var graphTemp     = true
    @AppStorage(GraphKey.wetBulb)  private var graphWetBulb  = false
    @AppStorage(GraphKey.dewPoint) private var graphDewPoint = false
    @AppStorage(GraphKey.feels)    private var graphFeels    = true
    @AppStorage(GraphKey.color)   private var graphColor   = true
    @AppStorage(GraphKey.precip)   private var graphPrecip   = true
    @AppStorage(GraphKey.wind)     private var graphWind     = true
    @AppStorage(GraphKey.gust)     private var graphGust     = true
    @AppStorage(GraphKey.sky)      private var graphSky      = true
    /// #3: when off, the table screen is dropped from the pager so swiping only
    /// cycles between the two graph screens.
    @AppStorage(SettingsKey.showTable)       private var showTable     = false
    @AppStorage(SettingsKey.useFoldTimeline) private var useFoldTimeline = false
    @Environment(\.scenePhase) private var scenePhase

    /// True when at least one forecast graph is enabled. When false, the 24h
    /// and 10-day screens are hidden and only the table remains.
    private var anyGraphVisible: Bool {
        graphTemp || graphWetBulb || graphDewPoint || graphFeels
            || graphColor || graphPrecip || graphWind || graphGust
    }

    /// True when the table screen is the one currently on-screen in the pager
    /// (or the only screen). The weather-sky background is suppressed there so
    /// the table stays readable (#2).
    private var onTableScreen: Bool {
        if !anyGraphVisible { return true }          // table is the only screen
        guard showTable else { return false }        // no table tab exists
        return useFoldTimeline ? zoomShowsTable : screen == .table
    }

    // Whole-screen weather-sky background (current conditions), shown behind
    // the title bar and bottom toolbar too — but not on the table screen.
    private var skyPoint: ForecastPoint? { weather.series24h.first ?? weather.current }
    private var skyIsDay: Bool {
        if let sr = weather.sunrise, let ss = weather.sunset { return nowTick >= sr && nowTick < ss }
        return skyPoint?.isDaylight ?? true
    }
    /// Whether the sky background is actually shown right now.
    private var showSky: Bool { graphSky && !onTableScreen }
    /// Legible ink over the sky: black by day, white by night (system otherwise).
    private var skyInk: Color { showSky ? (skyIsDay ? .black : .white) : .primary }

    @Environment(\.colorScheme) private var systemScheme
    /// Appearance for the chrome (chips, bottom bar) over the sky: light by day
    /// so the frosted capsules read white against the blue, dark by night — tied
    /// to the weather, not the phone's dark-mode setting. Follows the system when
    /// the sky is hidden.
    private var chromeScheme: ColorScheme { showSky ? (skyIsDay ? .light : .dark) : systemScheme }

    @Query(sort: \Rating.timestamp) private var ratings: [Rating]
    @State private var regressionState: RegressionState? = RegressionStateStore.load()
    @Environment(\.modelContext) private var modelContext
    /// One-shot wipe flag: when transitioning to the 0–1000 color-score
    /// system, all previously-collected ratings (and the stored regression
    /// state, which was trained against feelsLikeC) are discarded so the
    /// fresh score-based model can be built from new data.
    @AppStorage(SettingsKey.didWipeForScoreV1) private var didWipeForScoreV1: Bool = false
    /// One-shot: convert ratings from the previous color scale (see
    /// ScoreScaleMigration).
    @AppStorage(SettingsKey.didMigrateScoreScaleV2) private var didMigrateScoreScaleV2: Bool = false
    /// One-shot repair for a build that converted without re-uploading.
    @AppStorage(SettingsKey.didReuploadAfterScaleV2) private var didReuploadAfterScaleV2: Bool = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Size of the area the forecast is drawn in, measured rather than assumed.
    @State private var canvasSize: CGSize = .zero
    /// Measured height of the floating button bar, so the table can keep its
    /// last rows out from under it.
    @State private var bottomBarHeight: CGFloat = 0
    /// Full width of the panel, safe areas included — the crease is its middle.
    @State private var displayWidth: CGFloat = 0
    /// Where the split pane starts within that panel.
    @State private var splitOriginX: CGFloat = 0
    /// Width the left pane needs so the divider lands on the crease.
    private var creaseLeftWidth: CGFloat {
        guard displayWidth > 0 else { return 0 }
        return max(0, displayWidth / 2 - splitOriginX)
    }

    /// How the device is folded and how flat it lies. Only read for now: the
    /// thresholds that would drive a layout off it are still guesses.
    @StateObject private var posture = DevicePosture()

    private enum LayoutMode {
        /// One screen at a time, swiped between — a phone, or an unfolded
        /// foldable's outer screen.
        case pager
        /// Two panes side by side, on a canvas too small for the full dashboard.
        case splitPane
        /// The full iPad dashboard: both graphs side by side, table below.
        case dashboard
    }

    /// Smallest short side that still carries the three-pane dashboard.
    ///
    /// Measured on the short side rather than the width, because the width
    /// changes with orientation and the device does not: an unfolded iPhone Duo
    /// is 669 x 951 pt, so in landscape it is 951 pt wide and sails past any
    /// width test, taking a dashboard built for a 13-inch iPad. Its short side
    /// is 669 pt whichever way up it is held, against 744 pt for the smallest
    /// iPad, so the gap holds in both orientations.
    private static let dashboardMinShortSide: CGFloat = 700

    /// Which root layout to use. Size class alone cannot decide this any more:
    /// an unfolded foldable reports regular in *both* dimensions exactly as an
    /// iPad does, while being barely half its width, so without the measurement
    /// it would inherit a dashboard built for a 13-inch screen.
    private var layoutMode: LayoutMode {
        guard horizontalSizeClass == .regular, verticalSizeClass == .regular else { return .pager }
        // Before the first layout pass there is nothing to measure; keep the
        // iPad's existing behaviour rather than flashing a narrower one.
        guard canvasSize.width > 0, canvasSize.height > 0 else { return .dashboard }
        let shortSide = min(canvasSize.width, canvasSize.height)
        guard shortSide < Self.dashboardMinShortSide else { return .dashboard }
        // Only split across the crease. Open like a book the fold is vertical
        // and the panels sit side by side, which is the pose the split is for.
        // Turned upright the panels are above and below each other, so a
        // left/right split would straddle the fold — show the outer screen's
        // single-pane layout instead and leave the crease alone.
        return canvasSize.width > canvasSize.height ? .splitPane : .pager
    }

    /// Full-size iPad (not a narrow split view): show all three forecast
    /// screens on one dashboard instead of paging between them.
    private var useDashboardLayout: Bool { layoutMode == .dashboard }

    /// On the unfolded big screen the table is simply always there, in its own
    /// half. Nothing navigates to it, so the buttons that would are hidden and
    /// the Settings switch does not apply: the table lives there and nowhere
    /// else on this device.
    private var tableAlongside: Bool { layoutMode == .splitPane }

    /// Whether a button should offer to reach the table from a graph screen.
    private var tableIsReachable: Bool { showTable && !tableAlongside }

    /// Debug only: `-UITestCanvas 669x951` pins the layout to a given size, so
    /// the unfolded-foldable layout can be seen on an ordinary simulator. Absent
    /// the argument this is nil and nothing is constrained.
    private static let debugCanvas: CGSize? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-UITestCanvas"), i + 1 < args.count else { return nil }
        let parts = args[i + 1].lowercased().split(separator: "x")
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]) else { return nil }
        return CGSize(width: w, height: h)
    }()

    private var scenario: Scenario {
        Scenario(activity: scenarioActivity, dress: scenarioDress, sun: scenarioSun)
    }

    /// Features currently in the model.  Used to decide which scenario
    /// adjusters to show — only those that actually influence the
    /// prediction are exposed to the user.  Empty when no model is fit yet.
    private var activeFeatures: Set<Feature> {
        Set(regressionState?.selectedFeatures ?? [])
    }

    private func personalized(_ series: [ForecastPoint], splitSun: Bool = false) -> [ForecastPoint] {
        guard regressionState != nil else { return series }
        let s = regressionState
        let sc = scenario
        return series.map { p in
            var copy = p
            copy.applyPrediction(state: s, scenario: sc)
            // The 24h color band shows in-sun vs in-shade side by side.
            if splitSun { copy.applySunShadePrediction(state: s, scenario: sc) }
            return copy
        }
    }

    /// Whether the model actually learned a sun effect — the 24h color band
    /// only splits into sun/shade when it did (otherwise the halves are equal).
    private var sunFeatureActive: Bool { activeFeatures.contains(.sun) }

    private func personalized(_ point: ForecastPoint?) -> ForecastPoint? {
        guard let point else { return nil }
        return personalized([point]).first
    }

    private var displayTitle: String {
        if let name = selectedPlace?.name { return name }
        return weather.placeDescription.isEmpty ? "Loading…" : weather.placeDescription
    }

    var body: some View {
        mainContent
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomBarHeight = $0 }
        }
        .background {
            // Zero-sized host for the hinge interaction, which is UIKit-only.
            HingeReader { angle, status in posture.apply(angle: angle, status: status) }
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        .task { posture.start() }
        .background { skyBackground }
        // The whole panel, status corner and all — from the window, since a
        // SwiftUI background reports what is left after the safe area and
        // ignoresSafeArea() does not change that.
        .background {
            WindowWidthReader { displayWidth = $0 }
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $showPlaces) {
            NavigationStack {
                PlacesListView(
                    placesVM: places,
                    locationProvider: locationProvider,
                    currentWeather: weather,
                    onSelect: { place in
                        selectedPlace = place
                        showPlaces = false
                        Task { await loadWeather() }
                    }
                )
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showRate) {
            if let now = weather.series24h.first {
                RateFeelsLikeView(
                    snapshot: now,
                    placeID: selectedPlace?.id,
                    useFahrenheit: useFahrenheit
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView(forecast: weather.series10d,
                             placeName: weather.placeDescription)
            }
        }
        .sheet(isPresented: $showInfo) {
            NavigationStack { InfoView() }
        }
        // First launch (and after each update) introduce the app and offer the
        // guide. Open Info only once the welcome sheet has finished dismissing.
        .sheet(isPresented: $showWelcome, onDismiss: {
            lastSeenVersion = AppVersion.current
            if wantsGuide { wantsGuide = false; showInfo = true }
        }) {
            WelcomeSheet(isUpdate: !lastSeenVersion.isEmpty) { wantsGuide = true }
        }
        .onOpenURL { url in
            // A tapped `.myfeelslike` attachment arrives as a file URL; a scanned
            // QR or texted link as a myfeelslike:// URL. Both resolve to the same
            // ParsedInvite.
            guard let inv = url.isFileURL ? CompareShare.parseImportedFile(url)
                                          : CompareShare.parseInvite(url) else { return }
            // Persist immediately so it's there when Compare appears, then jump
            // to the Compare screen (CompareView also reacts to `incomingInvite`
            // if it's already open). `model` present ⇒ a scanned/texted snapshot.
            ComparePeerStore.add(shareID: inv.id, name: inv.name, embeddedModel: inv.model)
            incomingInvite = CompareInvite(id: inv.id, name: inv.name, token: inv.token,
                                           model: inv.model, nonce: UUID())
            showingCompare = true
        }
        .onReceive(locationProvider.$currentLocation.compactMap { $0 }) { loc in
            // Only fire on a location update when there is no data yet.
            // Prevents this from racing with pull-to-refresh or the
            // foreground auto-refresh and invalidating their loadGeneration.
            if !DemoMode.isActive && selectedPlace == nil && weather.series24h.isEmpty {
                Task { await weather.loadFor(location: loc) }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            pushToWatch()    // keep the watch's settings/model current
            // Auto-refresh when returning from background if data is ≥ 30 min old.
            // Use a fresh fix — the user may have moved while it was backgrounded.
            if let fetched = weather.lastFetchedAt,
               Date().timeIntervalSince(fetched) > 1800,
               !weather.isRefreshing {
                Task { await loadWeather(preserveData: true, useFreshLocation: true) }
            }
        }
        .task {
            if DemoMode.isActive {
                seedDemo()
                weather.loadDemo()
                applyScreenshotScreen()   // navigate for App Store screenshot capture
            } else {
                await loadWeather()
                places.refreshWeatherIfNeeded()
            }
        }
        .onChange(of: ratings.count) { _, _ in refitRegression() }
        .onAppear {
            PhoneWatchSync.shared.start()
            if !DemoMode.isActive && !didWipeForScoreV1 {
                for r in ratings { modelContext.delete(r) }
                try? modelContext.save()
                RegressionStateStore.save(nil)
                regressionState = nil
                didWipeForScoreV1 = true
            }
            // Ratings given on the previous color scale are converted once, so
            // upgrading testers keep them instead of mixing two scales in one
            // model. A fresh install has nothing to convert and just sets the
            // flag. refitRegression() below then refits on the new targets.
            if !DemoMode.isActive && !didMigrateScoreScaleV2 {
                let n = ScoreScaleMigration.migrate(ratings)
                if n > 0 {
                    try? modelContext.save()
                    // These ratings changed in place. The developer-data upload
                    // is a delta keyed on rating id, so without this the already
                    // uploaded copies would keep their old-scale scores and never
                    // gain score1 — the shared set would quietly mix both scales.
                    DeveloperDataSync.markAllForReupload()
                }
                didMigrateScoreScaleV2 = true
            }
            // Repair for anyone who installed the build where the conversion ran
            // without clearing the upload markers: their converted ratings were
            // never re-sent. Harmless for everyone else — records are keyed by
            // rating id and overwrite, so this costs one re-upload, once.
            if !DemoMode.isActive && !didReuploadAfterScaleV2 {
                DeveloperDataSync.markAllForReupload()
                didReuploadAfterScaleV2 = true
            }
            refitRegression()
            // Welcome on first launch; "what's new" after an update.
            if !DemoMode.isActive && lastSeenVersion != AppVersion.current {
                showWelcome = true
            }
        }
        // Turning the table off while on it would strand the user there.
        .onChange(of: showTable) { _, on in
            if !on {
                if screen == .table { screen = lastGraph }
                zoomShowsTable = false
            }
        }
        .onChange(of: shareData) { _, _ in syncDeveloperData() }   // opt in → upload, opt out → delete
        .onChange(of: useFahrenheit) { _, _ in pushToWatch() }
        .onChange(of: scenarioActivity) { _, _ in pushToWatch() }
        .onChange(of: scenarioDress) { _, _ in pushToWatch() }
        .onChange(of: scenarioSun) { _, _ in pushToWatch() }
        .onChange(of: places.places) { _, _ in pushToWatch() }
        .onReceive(progressTimer) { t in
            // Fast updates only while loading (for the progress hints); once a
            // minute otherwise — enough for the day/night sky to switch on time.
            let loading = weather.isRefreshing || weather.series24h.isEmpty
            if loading || t.timeIntervalSince(nowTick) >= 60 { nowTick = t }
        }
    }

    // MARK: Body sub-views (kept small so the type-checker doesn't choke)

    /// Title bar on top + the active forecast layout below it (or the Compare
    /// screen when it's showing).
    @ViewBuilder
    private var mainContent: some View {
        Group {
            if showingCompare {
                CompareView(nearby: nearby,
                            ownSeries: weather.isRefreshing ? [] : bandSeries(regressionState),
                            bandSeries: bandSeries,
                            ownModel: regressionState,
                            ownSunSplit: sunFeatureActive,
                            invite: incomingInvite,
                            ink: skyInk,
                            systemScheme: systemScheme)
            } else {
                forecastContent
            }
        }
        // Chips/buttons follow the weather's day/night, not the phone's dark-mode
        // setting, so they stay white over the daytime sky. Sheets attached out
        // here in `body` don't inherit this, but ones presented from *inside*
        // this subtree do — CompareView takes `systemScheme` to undo it.
        .environment(\.colorScheme, chromeScheme)
        .environment(\.skyIsVisible, showSky)
        // Publish the same flag the sky itself is drawn from, so no subview
        // can reach a different conclusion about which ink is legible.
        .environment(\.skyIsDay, skyIsDay)
    }

    /// A color-band series: a given model applied to *our* local 24h forecast
    /// (with the current scenario), so every compared band is for the same
    /// weather and differs only by the personal model. Used for "You" and peers.
    private func bandSeries(_ model: RegressionState?) -> [ForecastPoint] {
        let sc = scenario
        let split = model?.selectedFeatures.contains(.sun) ?? false
        return weather.series24h.map { p in
            var copy = p
            copy.applyPrediction(state: model, scenario: sc)
            if split { copy.applySunShadePrediction(state: model, scenario: sc) }
            return copy
        }
    }

    @ViewBuilder
    private var forecastContent: some View {
        measuredForecastContent
            .frame(width: Self.debugCanvas?.width, height: Self.debugCanvas?.height)
    }

    @ViewBuilder
    private var measuredForecastContent: some View {
        VStack(spacing: 0) {
            titleButton
            if !showSky { Divider() }

            if !anyGraphVisible {
                // #10: every graph disabled → only the table screen remains.
                forecastTableTab(chipFeatures: activeFeatures)
            } else if useFoldTimeline && layoutMode == .pager && showTable && zoomShowsTable {
                forecastTableTab(chipFeatures: activeFeatures)
            } else if useFoldTimeline && layoutMode == .pager {
                // Experimental single morphing timeline in place of the two paged
                // graph screens. Its own left/right swipe drives the 24h↔10-day
                // morph, so it takes over paging (the table isn't reachable here
                // yet — the scrubber readout covers reading exact values).
                foldTimelineTab
            } else if layoutMode == .splitPane {
                splitPaneLayout
            } else if useDashboardLayout {
                dashboardLayout
            } else {
                graphPager
            }
        }
        // Measure what we actually got, rather than inferring it from the
        // device. This is what tells an unfolded foldable from an iPad.
        .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
    }

    /// Fixed place name – taps open the places sheet.
    /// Centered place name (taps open Places) with an ⓘ at the trailing edge
    /// that opens the Info screen — the bottom bar is already busy enough.
    private var titleButton: some View {
        ZStack {
            Button { showPlaces = true } label: {
                Text(displayTitle)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(skyInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal)
            }
            .buttonStyle(.plain)

            HStack {
                // Refresh lives here because the vertical swipe that used to
                // pull-to-refresh now switches screens.
                Button {
                    Task { await loadWeather(preserveData: true, useFreshLocation: true) }
                } label: {
                    Group {
                        if weather.isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .font(.body)
                    .foregroundStyle(skyInk)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(weather.isRefreshing)
                .accessibilityLabel("Refresh forecast")
                .accessibilityIdentifier("refreshButton")

                Spacer()
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.body)
                        .foregroundStyle(skyInk)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About MyFeelsLike")
                .accessibilityIdentifier("infoButton")
            }
        }
        .background(showSky ? AnyShapeStyle(.clear) : AnyShapeStyle(.bar))
    }

    /// Unfolded foldable: the table beside the screen you were already on, so
    /// opening the device adds to what you were looking at rather than
    /// replacing it. Which half each lands on is still open — swapping the two
    /// is a matter of reordering this HStack.
    @ViewBuilder
    private var splitPaneLayout: some View {
        ScenarioStrip(activeFeatures: activeFeatures)
        // Even halves, because the halves are physical: the right one has to
        // land on the panel that carries the outer screen, so that opening the
        // device reads as the folding half turning transparent rather than as
        // the layout rearranging itself.
        //
        // Both panes are simply flexible rather than measured by a
        // GeometryReader: the reader took the full height and laid its children
        // out inside it, which swallowed the bottom safe-area inset and ran the
        // table underneath the button bar.
        HStack(spacing: 0) {
            forecastTableTab(chipFeatures: [])
                // A little air at the screen edge: the score column was running
                // straight into it.
                .padding(.leading, 8)
                // Fixed, not capped: a cap only stops the pane growing past the
                // crease, and the stack was handing it less than that anyway —
                // which left the graph starting before the fold even though the
                // crease itself was worked out correctly.
                .frame(width: creaseLeftWidth > 0 ? creaseLeftWidth : nil)
                // End the table above the button bar rather than letting it
                // scroll underneath. A scroll view is happy to run its content
                // under a floating bar — which is right for one screen you
                // scroll, and wrong for a pane sitting permanently beside
                // another, where rows just disappear behind the buttons.
                .padding(.bottom, bottomBarHeight)
            Divider()
            phoneContentPane
                .frame(maxWidth: .infinity)
        }
        // The crease is the middle of the panel. Reconstructing the panel width
        // from safe-area insets was guesswork and landed the divider left of
        // the fold; the panel is measured directly instead (see displayWidth),
        // and this reports where the split starts inside it.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).minX
        } action: { splitOriginX = $0 }
    }

    /// Whatever the outer screen shows: the paged graphs, or the zoom graph
    /// when that is switched on.
    @ViewBuilder
    private var phoneContentPane: some View {
        if useFoldTimeline { foldTimelineTab } else { graphPager }
    }

    /// iPad dashboard: 24h + 10-day side by side, table below (scrolling in its
    /// panel). A single scenario strip up here replaces the per-screen ones.
    @ViewBuilder
    private var dashboardLayout: some View {
        ScenarioStrip(activeFeatures: activeFeatures)
        GeometryReader { geo in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    hereTodayTab(chipFeatures: [], fitsPane: true)
                    Divider()
                    tenDayTab(chipFeatures: [], fitsPane: true)
                }
                .frame(height: showTable ? geo.size.height * 0.55 : geo.size.height)
                if showTable {
                    Divider()
                    forecastTableTab(chipFeatures: [])
                }
            }
        }
    }

    /// iPhone pager including the table (5-tab circular wrap):
    ///   0 = table phantom → real 3, 1 = 24h (default), 2 = 10d, 3 = table,
    ///   4 = 24h phantom → real 1. Phantoms show identical content; onChange
    ///   teleports to the real tab with no animation so the jump is invisible.
    /// The graph screens, paged by drag rather than by TabView: a horizontal
    /// swipe pans time, a vertical swipe switches screen. The table is not in
    /// the vertical cycle — it is reached from the header, because a screen
    /// that scrolls ten days needs a way back that isn't a gesture.
    private var graphPager: some View {
        GeometryReader { geo in
            let hgt = geo.size.height
            ZStack {
                // The screen being dragged towards, parked just off the edge so
                // it slides in with the finger.
                if dragY != 0 {
                    screenView(screen.advanced(by: dragY < 0 ? 1 : -1,
                                               includeTable: false))
                        .offset(y: dragY < 0 ? hgt + dragY : -hgt + dragY)
                }
                screenView(screen).offset(y: dragY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
            // The table owns its own vertical scrolling, so it opts out.
            .gesture(screen == .table ? nil : graphDrag(size: geo.size))
        }
    }

    @ViewBuilder
    private func screenView(_ s: ForecastScreen) -> some View {
        switch s {
        case .today:  hereTodayTab(chipFeatures: activeFeatures)
        case .tenDay: tenDayTab(chipFeatures: activeFeatures)
        case .table:  forecastTableTab(chipFeatures: activeFeatures)
        }
    }

    /// Horizontal drag pans the time window; vertical drag switches screens.
    /// The axis is decided once per drag so a diagonal doesn't do both.
    private func graphDrag(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { v in
                if dragAxis == nil {
                    dragAxis = abs(v.translation.width) >= abs(v.translation.height)
                        ? .horizontal : .vertical
                }
                if dragAxis == .vertical {
                    dragY = v.translation.height
                    return
                }
                if panBase == nil { panBase = startOffset }
                // Dragging a full screen width pans by one window span.
                let span = screen.span
                let dt = -Double(v.translation.width) / Double(max(1, size.width)) * span
                startOffset = clampedOffset((panBase ?? startOffset) + dt)
            }
            .onEnded { v in
                let axis = dragAxis
                dragAxis = nil; panBase = nil
                guard axis == .vertical else { return }
                let dy = v.translation.height
                let step = dy < 0 ? 1 : -1
                // Carry the screen the rest of the way if the swipe was
                // decisive, otherwise let it fall back.
                if abs(dy) > 60 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        dragY = dy < 0 ? -size.height : size.height
                    } completion: {
                        screen = screen.advanced(by: step, includeTable: false)
                        startOffset = clampedOffset(startOffset)
                        dragY = 0
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { dragY = 0 }
                }
            }
    }

    private func clampedOffset(_ o: TimeInterval) -> TimeInterval {
        TimelineScroll.clampStartOffset(o, span: screen.span, now: nowTick,
                                        dataLo: panSeries.first?.date,
                                        dataHi: panSeries.last?.date)
    }

    /// Left edge of the visible window.
    private var windowStart: Date { nowTick.addingTimeInterval(startOffset) }

    /// The full −10d…+10d series the graph screens pan over. History arrives
    /// after the forecast, so this is forecast-only for the first moment.
    private var panSeries: [ForecastPoint] {
        let hist = weather.historic
        guard !hist.isEmpty else { return weather.series10d }
        return hist + weather.series10d
    }

    /// The slice of `panSeries` a screen actually draws, padded either side so
    /// curves reach both edges. Slicing before personalising matters: the model
    /// runs per point, and a pan would otherwise re-predict ten days of hours
    /// on every frame of the drag.
    private func panWindow(_ span: TimeInterval) -> [ForecastPoint] {
        let lo = windowStart.addingTimeInterval(-span * 0.03 - 2 * 3600)
        let hi = windowStart.addingTimeInterval(span + 2 * 3600)
        return panSeries.filter { $0.date >= lo && $0.date <= hi }
    }

    /// The window split back into observed past and forecast. The 10-day screen
    /// keeps them apart so history stays dashed and the forecast solid.
    private func panWindowSplit(_ span: TimeInterval)
        -> (historic: [ForecastPoint], forecast: [ForecastPoint]) {
        let w = panWindow(span)
        return (w.filter { $0.kind == .historic }, w.filter { $0.kind != .historic })
    }

    /// Screen title, with the window's date once the user has scrolled off "now".
    private func windowLabel(_ s: ForecastScreen) -> String {
        let drift = abs(windowStart.timeIntervalSince(nowTick))
        guard drift > 3600 else { return s.title }
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEEd MMM")
        return "\(s.title) · \(f.string(from: windowStart))"
    }

    /// Title with buttons to the screens the user is not on. Gestures alone are
    /// impractical for reaching a screen now that the graphs scroll ten days.
    private func headerBar(_ title: String,
                           left: (String, () -> Void)? = nil,
                           right: (String, () -> Void)? = nil) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(showSky ? skyInk : .secondary)
                    .lineLimit(1).minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 78)
                HStack {
                    if let left { Button(left.0) { left.1() } }
                    Spacer()
                    if let right { Button(right.0) { right.1() } }
                }
                .font(.subheadline)
                .foregroundStyle(showSky ? skyInk : Color.accentColor)
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 5)
            .background(showSky ? AnyShapeStyle(.clear) : AnyShapeStyle(.bar))
            if !showSky { Divider() }
        }
    }

    /// Entering the table: line it up with the moment the graph is showing.
    private func goToTable() {
        tableTopDate = windowStart
        if screen != .table { lastGraph = screen }
        withAnimation(.easeInOut(duration: 0.25)) {
            if useFoldTimeline { zoomShowsTable = true } else { screen = .table }
        }
    }

    /// Leaving the table: start the graph at the table's top visible row, so the
    /// two screens stay on the same moment in time.
    private func leaveTable(to target: ForecastScreen?) {
        let dest = target ?? lastGraph
        if let d = tableTopDate {
            // Clamp against the span of the screen we are going TO. Using the
            // table's own ten-day span would pin any future date back to "now",
            // because a ten-day window cannot start later than that.
            let span = useFoldTimeline ? ForecastScreen.today.span : dest.span
            startOffset = TimelineScroll.clampStartOffset(
                d.timeIntervalSince(nowTick), span: span, now: nowTick,
                dataLo: panSeries.first?.date,
                dataHi: panSeries.last?.date)
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            if useFoldTimeline { zoomShowsTable = false } else { screen = dest }
        }
    }

    private func goToScreen(_ s: ForecastScreen) {
        withAnimation(.easeInOut(duration: 0.25)) {
            screen = s
            startOffset = clampedOffset(startOffset)
        }
    }

    /// Bottom toolbar: Places · Rate · Compare · Settings, spread evenly across
    /// the width. Each is a frosted capsule "chip" matching the scenario chips at
    /// the top of the main screens, so the controls read consistently over the
    /// (sometimes busy) sky background.
    private var bottomBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button { showPlaces = true } label: {
                bottomChip(Label("Places", systemImage: "mappin.and.ellipse"))
            }
            .accessibilityIdentifier("placesButton")

            Spacer(minLength: 0)
            Button { showRate = true } label: {
                bottomChip(Label("Rate Feels Like", systemImage: "thermometer.medium"))
            }
            .disabled(weather.series24h.isEmpty)
            .accessibilityIdentifier("rateButton")

            Spacer(minLength: 0)
            compareButton

            Spacer(minLength: 0)
            Button { showSettings = true } label: {
                bottomChip(Image(systemName: "gearshape").font(.callout))
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settingsButton")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .environment(\.colorScheme, chromeScheme)
    }

    /// Frosted-capsule chip style shared by every bottom-bar control (matches the
    /// scenario chips at the top of the screens). A 44 pt min tap target wraps
    /// the smaller visible capsule.
    private func bottomChip<V: View>(_ content: V) -> some View {
        content
            .font(.caption.weight(.medium))
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5))
            .frame(minHeight: 44)
            .contentShape(Capsule())
    }

    /// Opens the Compare screen; becomes a back button while it's showing.
    @ViewBuilder
    private var compareButton: some View {
        if showingCompare {
            Button { showingCompare = false } label: {
                bottomChip(Label("Back", systemImage: "chevron.backward"))
            }
            .accessibilityLabel("Back")
            .accessibilityIdentifier("compareBackButton")
        } else {
            Button { showingCompare = true } label: {
                bottomChip(CompareIcon())
            }
            .accessibilityLabel("Compare with others")
            .accessibilityIdentifier("compareButton")
        }
    }

    /// #1: current-conditions sky filling the whole screen, behind the title
    /// bar and bottom toolbar too. Empty when the sky is disabled/unavailable.
    @ViewBuilder
    private var skyBackground: some View {
        if showSky, let sp = skyPoint {
            WeatherSkyView(point: sp, isDay: skyIsDay).ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func tabLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(showSky ? skyInk : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(showSky ? AnyShapeStyle(.clear) : AnyShapeStyle(.bar))
        if !showSky { Divider() }
    }

    private func refitRegression() {
        let new = FeelsLikeRegression.fit(ratings: ratings)
        regressionState = new
        RegressionStateStore.save(new)
        pushToWatch()
        nearby.updateLocalModel(new)   // live-update any compare peers
        // Pass the fresh model explicitly: `regressionState` is @State, and
        // reading it back in the same call isn't guaranteed to see the value we
        // just wrote — which silently uploaded ratings with no SharedModel.
        syncDeveloperData(model: new)
    }

    /// Upload anonymised ratings + model to CloudKit when the user has opted in
    /// (or delete them when they opt out). Never runs for demo/screenshot data.
    /// `model` defaults to the current state for callers outside a refit.
    private func syncDeveloperData(model: RegressionState? = nil) {
        guard !DemoMode.isActive else { return }
        DeveloperDataSync.sync(consent: shareData, ratings: ratings,
                               model: model ?? regressionState)
    }

    /// Navigate to a specific screen for App Store screenshot capture, driven by
    /// the `-UITestScreen <name>` launch argument (demo runs only). "today" is the
    /// default, so no arg is needed for it.
    private func applyScreenshotScreen() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-UITestScreen"), i + 1 < args.count else { return }
        switch args[i + 1] {
        case "tenday": screen = .tenDay
        case "table":  screen = .table
        // The sheets need presenting *after* the first layout settles — SwiftUI
        // drops an isPresented change made this early in the view's life, which
        // is why these used to be captured by tapping the bottom bar instead.
        case "places": presentAfterLaunch({ showPlaces }, { showPlaces = true })
        case "rate":   presentAfterLaunch({ showRate },   { showRate = true })
        case "info":   presentAfterLaunch({ showInfo },   { showInfo = true })
        default:       break                    // "today" → default tab 1
        }
    }

    /// Show a sheet once the screen behind it will actually keep it.
    ///
    /// SwiftUI silently drops an isPresented change made before the hierarchy
    /// has settled, and how long that takes varies enormously: a warm
    /// simulator accepts it almost immediately, while a cold one under
    /// screenshot-capture load swallowed every attempt for ~10 seconds. So
    /// this keeps asking twice a second until the flag sticks, then stops.
    /// Capped so a screen that never presents can't retry forever.
    private func presentAfterLaunch(_ isPresented: @escaping () -> Bool,
                                    _ show: @escaping () -> Void) {
        func attempt(_ n: Int) {
            guard n < 60 else { return }              // ~30s
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard !isPresented() else { return }
                show()
                attempt(n + 1)
            }
        }
        attempt(0)
    }

    /// Seed canned sample ratings + places for demo/screenshot runs (in-memory).
    private func seedDemo() {
        if ratings.isEmpty {
            for r in DemoMode.ratings() { modelContext.insert(r) }
            try? modelContext.save()
        }
        // Force demo places so the list matches the shown place name.
        places.places = DemoMode.places()
    }

    /// Send the current model + display settings + saved places to the watch.
    private func pushToWatch() {
        let placeDTOs = places.places.map {
            PlaceDTO(id: $0.id, name: $0.name, latitude: $0.latitude,
                     longitude: $0.longitude, altitude: $0.altitude)
        }
        PhoneWatchSync.shared.update(
            state: regressionState,
            useFahrenheit: useFahrenheit,
            activity: scenarioActivity, dress: scenarioDress, sun: scenarioSun,
            places: placeDTOs)
    }

    /// Load weather for the selected place, or the device's location. Set
    /// `useFreshLocation` for user-initiated refreshes (pull-to-refresh, return
    /// from background) so a moving user gets a fresh GPS fix rather than the
    /// last cached one; the first automatic load leaves it off and relies on the
    /// normal location callback.
    private func loadWeather(preserveData: Bool = false, useFreshLocation: Bool = false) async {
        if let place = selectedPlace {
            await weather.loadFor(location: place.clLocation, preserveData: preserveData)
        } else if useFreshLocation, let loc = await locationProvider.freshLocation() {
            await weather.loadFor(location: loc, preserveData: preserveData)
        } else if let loc = locationProvider.currentLocation {
            await weather.loadFor(location: loc, preserveData: preserveData)
        } else {
            locationProvider.requestLocation()
        }
    }

    // MARK: Tab content (used for both real and phantom tabs, and the iPad
    // dashboard panes). `chipFeatures` controls the embedded scenario strip:
    // the dashboard passes [] because it shows a single strip of its own.

    private func hereTodayTab(chipFeatures: Set<Feature>, fitsPane: Bool = false) -> some View {
        VStack(spacing: 0) {
            // The dashboard pane keeps the plain forecast slice and its own
            // label; only the paged screen scrolls.
            if fitsPane {
                tabLabel("24 hour forecast")
            } else {
                headerBar(windowLabel(.today),
                          left: ("10-day", { goToScreen(.tenDay) }),
                          right: tableIsReachable ? ("table", { goToTable() }) : nil)
            }
            HereTodayView(
                allSeries: weather.isRefreshing ? []
                    : personalized(fitsPane ? weather.series24h
                                            : panWindow(ForecastScreen.today.span), splitSun: true),
                windowStart: fitsPane ? nil : windowStart,
                windowSpan: ForecastScreen.today.span,
                current: weather.isRefreshing ? nil : personalized(weather.current),
                progress: weather.loadProgress,
                nowTick: nowTick,
                sunrise: weather.sunrise,
                sunset: weather.sunset,
                errorMessage: weather.lastErrorMessage,
                attribution: weather.attribution,
                onRefresh: { await loadWeather(preserveData: true, useFreshLocation: true) },
                activeFeatures: chipFeatures,
                sunFeatureActive: sunFeatureActive,
                fitsPane: fitsPane
            )
        }
    }

    private func tenDayTab(chipFeatures: Set<Feature>, fitsPane: Bool = false) -> some View {
        VStack(spacing: 0) {
            if fitsPane {
                tabLabel("10 day forecast")
            } else {
                headerBar(windowLabel(.tenDay),
                          left: ("24h", { goToScreen(.today) }),
                          right: tableIsReachable ? ("table", { goToTable() }) : nil)
            }
            TenDayView(
                series: weather.isRefreshing ? []
                    : personalized(fitsPane ? weather.series10d
                                            : panWindowSplit(ForecastScreen.tenDay.span).forecast,
                                   splitSun: sunFeatureActive),
                windowStart: fitsPane ? nil : windowStart,
                windowSpan: ForecastScreen.tenDay.span,
                historic: weather.isRefreshing ? []
                    : personalized(fitsPane ? weather.historic
                                            : panWindowSplit(ForecastScreen.tenDay.span).historic,
                                   splitSun: sunFeatureActive),
                current: weather.isRefreshing ? nil : personalized(weather.current),
                progress: weather.loadProgress,
                nowTick: nowTick,
                sunrise: weather.sunrise,
                sunset: weather.sunset,
                errorMessage: weather.lastErrorMessage,
                attribution: weather.attribution,
                onRefresh: { await loadWeather(preserveData: true, useFreshLocation: true) },
                activeFeatures: chipFeatures,
                modelReasons: modelReasons,
                fitsPane: fitsPane
            )
        }
    }

    private func foldTimelineTab(chipFeatures: Set<Feature>) -> some View {
        VStack(spacing: 0) {
            headerBar("graph", right: tableIsReachable ? ("table", { goToTable() }) : nil)
            FoldTimelineView(
                series: weather.isRefreshing ? [] : personalized(weather.series10d, splitSun: sunFeatureActive),
                historic: weather.isRefreshing ? [] : personalized(weather.historic, splitSun: sunFeatureActive),
                current: weather.isRefreshing ? nil : personalized(weather.current),
                progressLoad: weather.loadProgress,
                nowTick: nowTick,
                sunrise: weather.sunrise,
                sunset: weather.sunset,
                errorMessage: weather.lastErrorMessage,
                attribution: weather.attribution,
                onRefresh: { await loadWeather(preserveData: true, useFreshLocation: true) },
                startOffset: $startOffset,
                onShowTable: tableIsReachable ? { goToTable() } : nil,
                activeFeatures: chipFeatures
            )
        }
    }

    private var foldTimelineTab: some View { foldTimelineTab(chipFeatures: activeFeatures) }

    /// Why no personalized model yet (empty once one exists). Shown on the
    /// 10-day heatmap panel while it's gray.
    private var modelReasons: [String] {
        regressionState == nil ? FeelsLikeRegression.readinessReasons(ratings: ratings) : []
    }

    private func forecastTableTab(chipFeatures: Set<Feature>) -> some View {
        VStack(spacing: 0) {
            if tableAlongside {
                // Nothing to leave to: the graph is already in the other half.
                headerBar(ForecastScreen.table.title)
            } else if useFoldTimeline {
                headerBar(ForecastScreen.table.title,
                          left: ("graph", { leaveTable(to: nil) }))
            } else {
                headerBar(ForecastScreen.table.title,
                          left: ("24h", { leaveTable(to: .today) }),
                          right: ("10-day", { leaveTable(to: .tenDay) }))
            }
            ForecastTableView(
                weatherService: weather,
                nowTick: nowTick,
                onRefresh: { await loadWeather(preserveData: true, useFreshLocation: true) },
                personalize: { self.personalized($0) },
                activeFeatures: chipFeatures,
                // Beside the graph, over-scrolling the table just means you
                // reached the end of the table — it must not change screens.
                onSwitchScreen: tableAlongside ? nil : { _ in leaveTable(to: nil) },
                topDate: $tableTopDate
            )
        }
    }
}

#Preview {
    ContentView()
}
