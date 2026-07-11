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
    @State private var selectedTab = 1
    @AppStorage(SettingsKey.useFahrenheit) private var useFahrenheit: Bool = true
    @AppStorage(DeveloperDataSync.consentKey) private var shareData: Bool = false
    @AppStorage(SettingsKey.scenarioActivity) private var scenarioActivity: Int = 1
    @AppStorage(SettingsKey.scenarioDress)    private var scenarioDress:    Int = 0
    @AppStorage(SettingsKey.scenarioSun)      private var scenarioSun:      Int = 0
    @AppStorage(GraphKey.temp)     private var graphTemp     = true
    @AppStorage(GraphKey.wetBulb)  private var graphWetBulb  = true
    @AppStorage(GraphKey.dewPoint) private var graphDewPoint = true
    @AppStorage(GraphKey.feels)    private var graphFeels    = true
    @AppStorage(GraphKey.color)   private var graphColor   = true
    @AppStorage(GraphKey.precip)   private var graphPrecip   = true
    @AppStorage(GraphKey.wind)     private var graphWind     = true
    @AppStorage(GraphKey.gust)     private var graphGust     = true
    @AppStorage(GraphKey.sky)      private var graphSky      = true
    /// #3: when off, the table screen is dropped from the pager so swiping only
    /// cycles between the two graph screens.
    @AppStorage(SettingsKey.showTable)       private var showTable     = true
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
        return selectedTab == 0 || selectedTab == 3  // table phantom / real
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

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Full-size iPad (not a narrow split view): show all three forecast
    /// screens on one dashboard instead of paging between them.
    private var useDashboardLayout: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }

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
        .safeAreaInset(edge: .bottom) { bottomBar }
        .background { skyBackground }
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
            guard let (id, name, token) = CompareShare.parseInvite(url) else { return }
            // Persist immediately so it's there when Compare appears, then jump
            // to the Compare screen (CompareView also reacts to `incomingInvite`
            // if it's already open, and writes the acceptance back to the inviter).
            ComparePeerStore.add(shareID: id, name: name)
            incomingInvite = CompareInvite(id: id, name: name, token: token, nonce: UUID())
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
            if let fetched = weather.lastFetchedAt,
               Date().timeIntervalSince(fetched) > 1800,
               !weather.isRefreshing {
                Task { await loadWeather(preserveData: true) }
            }
        }
        .task {
            if DemoMode.isActive {
                seedDemo()
                weather.loadDemo()
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
            refitRegression()
            // Welcome on first launch; "what's new" after an update.
            if !DemoMode.isActive && lastSeenVersion != AppVersion.current {
                showWelcome = true
            }
        }
        .onChange(of: showTable) { _, _ in selectedTab = 1 }   // avoid a now-invalid tab tag
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
                            ink: skyInk)
            } else {
                forecastContent
            }
        }
        // Chips/buttons follow the weather's day/night, not the phone's dark-mode
        // setting, so they stay white over the daytime sky (sheets are unaffected).
        .environment(\.colorScheme, chromeScheme)
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
        VStack(spacing: 0) {
            titleButton
            if !showSky { Divider() }

            if !anyGraphVisible {
                // #10: every graph disabled → only the table screen remains.
                forecastTableTab(chipFeatures: activeFeatures)
            } else if useDashboardLayout {
                dashboardLayout
            } else if showTable {
                tabPagerWithTable
            } else {
                tabPagerNoTable
            }
        }
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
    private var tabPagerWithTable: some View {
        TabView(selection: $selectedTab) {
            forecastTableTab(chipFeatures: activeFeatures).tag(0)
            hereTodayTab(chipFeatures: activeFeatures).tag(1)
            tenDayTab(chipFeatures: activeFeatures).tag(2)
            forecastTableTab(chipFeatures: activeFeatures).tag(3)
            hereTodayTab(chipFeatures: activeFeatures).tag(4)
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .onChange(of: selectedTab) { _, tab in
            guard tab == 0 || tab == 4 else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { selectedTab = tab == 0 ? 3 : 1 }
        }
    }

    /// iPhone pager with the table hidden (#3): 4-tab circular wrap over the two
    /// graph screens — 0 = 10d phantom → real 2, 1 = 24h (default), 2 = 10d,
    /// 3 = 24h phantom → real 1.
    private var tabPagerNoTable: some View {
        TabView(selection: $selectedTab) {
            tenDayTab(chipFeatures: activeFeatures).tag(0)
            hereTodayTab(chipFeatures: activeFeatures).tag(1)
            tenDayTab(chipFeatures: activeFeatures).tag(2)
            hereTodayTab(chipFeatures: activeFeatures).tag(3)
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .onChange(of: selectedTab) { _, tab in
            guard tab == 0 || tab == 3 else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { selectedTab = tab == 0 ? 2 : 1 }
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
        syncDeveloperData()            // upload new rating + model if opted in
    }

    /// Upload anonymised ratings + model to CloudKit when the user has opted in
    /// (or delete them when they opt out). Never runs for demo/screenshot data.
    private func syncDeveloperData() {
        guard !DemoMode.isActive else { return }
        DeveloperDataSync.sync(consent: shareData, ratings: ratings, model: regressionState)
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

    private func loadWeather(preserveData: Bool = false) async {
        if let place = selectedPlace {
            await weather.loadFor(location: place.clLocation, preserveData: preserveData)
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
            tabLabel("24 hour forecast")
            HereTodayView(
                series: weather.isRefreshing ? [] : personalized(weather.series24h, splitSun: true),
                current: weather.isRefreshing ? nil : personalized(weather.current),
                progress: weather.loadProgress,
                nowTick: nowTick,
                sunrise: weather.sunrise,
                sunset: weather.sunset,
                errorMessage: weather.lastErrorMessage,
                attribution: weather.attribution,
                onRefresh: { await loadWeather(preserveData: true) },
                activeFeatures: chipFeatures,
                sunFeatureActive: sunFeatureActive,
                fitsPane: fitsPane
            )
        }
    }

    private func tenDayTab(chipFeatures: Set<Feature>, fitsPane: Bool = false) -> some View {
        VStack(spacing: 0) {
            tabLabel("10 day forecast")
            TenDayView(
                series: weather.isRefreshing ? [] : personalized(weather.series10d, splitSun: sunFeatureActive),
                historic: weather.isRefreshing ? [] : personalized(weather.historic, splitSun: sunFeatureActive),
                current: weather.isRefreshing ? nil : personalized(weather.current),
                progress: weather.loadProgress,
                nowTick: nowTick,
                sunrise: weather.sunrise,
                sunset: weather.sunset,
                errorMessage: weather.lastErrorMessage,
                attribution: weather.attribution,
                onRefresh: { await loadWeather(preserveData: true) },
                activeFeatures: chipFeatures,
                modelReasons: modelReasons,
                fitsPane: fitsPane
            )
        }
    }

    /// Why no personalized model yet (empty once one exists). Shown on the
    /// 10-day heatmap panel while it's gray.
    private var modelReasons: [String] {
        regressionState == nil ? FeelsLikeRegression.readinessReasons(ratings: ratings) : []
    }

    private func forecastTableTab(chipFeatures: Set<Feature>) -> some View {
        VStack(spacing: 0) {
            tabLabel("table")
            ForecastTableView(
                weatherService: weather,
                nowTick: nowTick,
                onRefresh: { await loadWeather(preserveData: true) },
                personalize: { self.personalized($0) },
                activeFeatures: chipFeatures
            )
        }
    }
}

#Preview {
    ContentView()
}
