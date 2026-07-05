import SwiftUI
import Charts
import CoreLocation
import Combine
import SwiftData

// ForecastPoint now lives in ForecastPoint.swift (shared with the watch app).

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
    /// Text colour — follows the sky (black by day, white by night) so labels
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

// MARK: - Graph visibility settings (user-toggleable in Settings)

/// @AppStorage keys for which graph series the user wants to see. All default
/// to true. Shared by the forecast views, ContentView (tab gating) and Settings.
enum GraphKey {
    static let temp     = "graphTemp"
    static let wetBulb  = "graphWetBulb"
    static let dewPoint = "graphDewPoint"
    static let feels    = "graphFeels"
    static let colour   = "graphColour"
    static let precip   = "graphPrecip"
    static let wind     = "graphWind"
    static let gust     = "graphGust"
    static let sky      = "graphSky"

    /// True when at least one graph series is enabled (any forecast panel would
    /// show). When false, the 24h/10-day screens are hidden entirely.
    static func anyGraphEnabled(_ d: UserDefaults = .standard) -> Bool {
        let all = [temp, wetBulb, dewPoint, feels, colour, precip, wind, gust]
        // Missing key defaults to true (on).
        return all.contains { d.object(forKey: $0) == nil || d.bool(forKey: $0) }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var locationProvider = LocationProvider()
    @StateObject private var weather = WeatherService()
    @StateObject private var places = PlacesViewModel()
    @State private var selectedPlace: Place? = nil
    @State private var nowTick: Date = .now
    private let progressTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var showPlaces   = false
    @State private var showRate     = false
    @State private var showSettings = false
    // Tab indices: 0 = table phantom, 1 = 24h (real), 2 = 10d (real),
    //              3 = table (real), 4 = 24h phantom  — for circular wrap.
    @State private var selectedTab = 1
    @AppStorage("useFahrenheit") private var useFahrenheit: Bool = true
    @AppStorage("scenarioActivity") private var scenarioActivity: Int = 1
    @AppStorage("scenarioDress")    private var scenarioDress:    Int = 0
    @AppStorage("scenarioSun")      private var scenarioSun:      Int = 0
    @AppStorage(GraphKey.temp)     private var graphTemp     = true
    @AppStorage(GraphKey.wetBulb)  private var graphWetBulb  = true
    @AppStorage(GraphKey.dewPoint) private var graphDewPoint = true
    @AppStorage(GraphKey.feels)    private var graphFeels    = true
    @AppStorage(GraphKey.colour)   private var graphColour   = true
    @AppStorage(GraphKey.precip)   private var graphPrecip   = true
    @AppStorage(GraphKey.wind)     private var graphWind     = true
    @AppStorage(GraphKey.gust)     private var graphGust     = true
    @Environment(\.scenePhase) private var scenePhase

    /// True when at least one forecast graph is enabled. When false, the 24h
    /// and 10-day screens are hidden and only the table remains.
    private var anyGraphVisible: Bool {
        graphTemp || graphWetBulb || graphDewPoint || graphFeels
            || graphColour || graphPrecip || graphWind || graphGust
    }

    @Query(sort: \Rating.timestamp) private var ratings: [Rating]
    @State private var regressionState: RegressionState? = RegressionStateStore.load()
    @Environment(\.modelContext) private var modelContext
    /// One-shot wipe flag: when transitioning to the 0–1000 colour-score
    /// system, all previously-collected ratings (and the stored regression
    /// state, which was trained against feelsLikeC) are discarded so the
    /// fresh score-based model can be built from new data.
    @AppStorage("didWipeForScoreV1") private var didWipeForScoreV1: Bool = false

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

    private func personalised(_ series: [ForecastPoint]) -> [ForecastPoint] {
        guard regressionState != nil else { return series }
        let s = regressionState
        let sc = scenario
        return series.map { p in
            var copy = p
            copy.applyPrediction(state: s, scenario: sc)
            return copy
        }
    }

    private func personalised(_ point: ForecastPoint?) -> ForecastPoint? {
        guard let point else { return nil }
        return personalised([point]).first
    }

    private var displayTitle: String {
        if let name = selectedPlace?.name { return name }
        return weather.placeDescription.isEmpty ? "Loading…" : weather.placeDescription
    }

    var body: some View {
        VStack(spacing: 0) {
            // Line 1: fixed place name – taps open the places sheet
            Button { showPlaces = true } label: {
                Text(displayTitle)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal)
            }
            .background(.bar)

            Divider()

            if !anyGraphVisible {
                // #10: every graph disabled → only the table screen remains.
                forecastTableTab(chipFeatures: activeFeatures)
            } else if useDashboardLayout {
                // iPad: all three screens on one dashboard — 24h and 10-day
                // side by side on top, table below (scrolling in its panel).
                // A single scenario strip up here replaces the per-screen ones.
                ScenarioStrip(activeFeatures: activeFeatures)
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            hereTodayTab(chipFeatures: [], fitsPane: true)
                            Divider()
                            tenDayTab(chipFeatures: [], fitsPane: true)
                        }
                        .frame(height: geo.size.height * 0.55)
                        Divider()
                        forecastTableTab(chipFeatures: [])
                    }
                }
            } else {
                // 5-tab layout for circular (wrap-around) swiping:
                //   0 = table phantom  →  real tab is 3
                //   1 = 24h (real, default)
                //   2 = 10d (real)
                //   3 = table (real)
                //   4 = 24h phantom  →  real tab is 1
                // Phantoms show identical content; onChange teleports to the real
                // tab instantly (no animation) so the user never notices the jump.
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
        }
        .safeAreaInset(edge: .bottom) {
            ZStack {
                // Center area: Places + Rate Feels Like, side by side
                HStack(spacing: 24) {
                    Button { showPlaces = true } label: {
                        Label("Places", systemImage: "mappin.and.ellipse")
                            .padding(.vertical, 10)
                    }
                    .accessibilityIdentifier("placesButton")
                    Button { showRate = true } label: {
                        Label("Rate Feels Like", systemImage: "thermometer.medium")
                            .padding(.vertical, 10)
                    }
                    .disabled(weather.series24h.isEmpty)
                    .accessibilityIdentifier("rateButton")
                }

                HStack {
                    Spacer()

                    // Settings cog – bottom-right corner
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                    }
                    .accessibilityIdentifier("settingsButton")
                }
            }
            .background(.bar)
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
        }
        .onChange(of: useFahrenheit) { _, _ in pushToWatch() }
        .onChange(of: scenarioActivity) { _, _ in pushToWatch() }
        .onChange(of: scenarioDress) { _, _ in pushToWatch() }
        .onChange(of: scenarioSun) { _, _ in pushToWatch() }
        .onChange(of: places.places) { _, _ in pushToWatch() }
        .onReceive(progressTimer) { nowTick = $0 }
    }

    @ViewBuilder
    private func tabLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(.bar)
        Divider()
    }

    private func refitRegression() {
        let new = FeelsLikeRegression.fit(ratings: ratings)
        regressionState = new
        RegressionStateStore.save(new)
        pushToWatch()
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
                series: weather.isRefreshing ? [] : personalised(weather.series24h),
                current: weather.isRefreshing ? nil : personalised(weather.current),
                progress: weather.loadProgress,
                nowTick: nowTick,
                errorMessage: weather.lastErrorMessage,
                attribution: weather.attribution,
                onRefresh: { await loadWeather(preserveData: true) },
                activeFeatures: chipFeatures,
                fitsPane: fitsPane
            )
        }
    }

    private func tenDayTab(chipFeatures: Set<Feature>, fitsPane: Bool = false) -> some View {
        VStack(spacing: 0) {
            tabLabel("10 day forecast")
            TenDayView(
                series: weather.isRefreshing ? [] : personalised(weather.series10d),
                historic: weather.isRefreshing ? [] : personalised(weather.historic),
                current: weather.isRefreshing ? nil : personalised(weather.current),
                progress: weather.loadProgress,
                nowTick: nowTick,
                errorMessage: weather.lastErrorMessage,
                attribution: weather.attribution,
                onRefresh: { await loadWeather(preserveData: true) },
                activeFeatures: chipFeatures,
                modelReasons: modelReasons,
                fitsPane: fitsPane
            )
        }
    }

    /// Why no personalised model yet (empty once one exists). Shown on the
    /// 10-day heatmap panel while it's grey.
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
                personalise: { self.personalised($0) },
                activeFeatures: chipFeatures
            )
        }
    }
}

// MARK: - HereTodayView

struct HereTodayView: View {
    var series: [ForecastPoint]
    /// Apple's current-conditions nowcast, drawn as prominent "now" dots in a
    /// small gap to the left of the forecast curves.
    var current: ForecastPoint? = nil
    var progress: LoadProgress = LoadProgress()
    var nowTick: Date = .now
    var errorMessage: String? = nil
    var attribution: WeatherAttributionInfo? = nil
    var onRefresh: (() async -> Void)? = nil
    /// Features currently in the regression model. Used to decide which
    /// scenario adjusters to show. Empty = no model, no chips shown.
    var activeFeatures: Set<Feature> = []
    /// True when embedded in a fixed-height dashboard pane (iPad): panel
    /// fractions shrink so everything fits without scrolling.
    var fitsPane: Bool = false

    @AppStorage("useFahrenheit") private var useFahrenheit: Bool = true
    @AppStorage(GraphKey.temp)     private var graphTemp     = true
    @AppStorage(GraphKey.wetBulb)  private var graphWetBulb  = true
    @AppStorage(GraphKey.dewPoint) private var graphDewPoint = true
    @AppStorage(GraphKey.feels)    private var graphFeels    = true
    @AppStorage(GraphKey.colour)   private var graphColour   = true
    @AppStorage(GraphKey.precip)   private var graphPrecip   = true
    @AppStorage(GraphKey.wind)     private var graphWind     = true
    @AppStorage(GraphKey.gust)     private var graphGust     = true
    @AppStorage(GraphKey.sky)      private var graphSky      = true
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var tempPanelVisible: Bool { graphTemp || graphWetBulb || graphDewPoint || graphFeels }
    private var colourPanelVisible: Bool { graphColour }
    private var windPanelVisible: Bool { graphPrecip || graphWind || graphGust }

    private var tempLegendEntries: [(color: Color, label: String, isArea: Bool)] {
        var e: [(color: Color, label: String, isArea: Bool)] = []
        if graphFeels    { e.append((.purple, "MyFeelsLike", false)) }
        if graphTemp     { e.append((.blue,   "Temp",        false)) }
        if graphWetBulb  { e.append((.green,  "Wet Bulb",    false)) }
        if graphDewPoint { e.append((.red,    "Dew Pt",      false)) }
        return e
    }

    private var windLegendEntries: [(color: Color, label: String, isArea: Bool)] {
        var e: [(color: Color, label: String, isArea: Bool)] = []
        if graphPrecip { e.append((.blue, "Precip %", true)) }
        if graphWind   { e.append((.red,  useFahrenheit ? "Wind mph" : "Wind kph", false)) }
        if graphGust   { e.append((.red.opacity(0.5), useFahrenheit ? "Gust mph" : "Gust kph", false)) }
        return e
    }

    /// Normalised panel heights over whichever panels are enabled. The colour
    /// band is deliberately thin; `usable` < 1 leaves room for the panel
    /// labels + scenario strip + attribution so everything fits without
    /// scrolling.
    private func panelHeights(_ h: CGFloat) -> (temp: CGFloat, colour: CGFloat, wind: CGFloat) {
        let wT = tempPanelVisible ? 0.50 : 0
        let wC = colourPanelVisible ? 0.08 : 0
        let wW = windPanelVisible ? 0.36 : 0
        let tot = wT + wC + wW
        guard tot > 0 else { return (0, 0, 0) }
        let usable = h * (fitsPane ? 0.90 : 0.84)
        return (usable * wT / tot, usable * wC / tot, usable * wW / tot)
    }

    /// Domain begins ~1 h before "now" so the forecast curves sit slightly to
    /// the right, leaving a gap on the left for the prominent current dots.
    private var dateDomain: ClosedRange<Date>? {
        guard let last = series.last?.date else { return nil }
        let lo: Date
        if let c = current?.date {
            lo = c.addingTimeInterval(-3600)
        } else if let first = series.first?.date {
            lo = first
        } else {
            return nil
        }
        return lo...last
    }

    private static let hourFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "HH"
        return df
    }()

    private func hourLabel(for date: Date) -> String {
        HereTodayView.hourFormatter.string(from: date)
    }

    /// Whether the forecast carries personalised feels-like scores.
    private var hasModel: Bool {
        series.contains { $0.myFeelsLikeScore != nil }
    }

    /// Tight y-range covering the four temperature curves (+ the current dots),
    /// used as the explicit scale so the filled bands have a defined baseline.
    private var tempYDomain: ClosedRange<Double> {
        var vals: [Double] = []
        for p in series + (current.map { [$0] } ?? []) {
            if graphTemp     { vals.append(useFahrenheit ? p.temperatureF : p.temperatureC) }
            if graphWetBulb  { vals.append(useFahrenheit ? p.wetBulbF : p.wetBulbC) }
            if graphDewPoint { vals.append(useFahrenheit ? p.dewPointF : p.dewPointC) }
            if graphFeels    { vals.append(useFahrenheit ? p.apparentTemperatureF : p.apparentTemperatureC) }
        }
        guard let lo = vals.min(), let hi = vals.max() else { return 0...1 }
        let pad = max(1, (hi - lo) * 0.08)
        return (lo - pad)...(hi + pad)
    }

    /// y-range for the precip/wind chart, always anchored at 0 so the filled
    /// areas have a sensible baseline.
    private var windYDomain: ClosedRange<Double> {
        var vals: [Double] = []
        for p in series + (current.map { [$0] } ?? []) {
            if graphPrecip { vals.append(p.precipProbability * 100) }
            if graphGust   { vals.append(useFahrenheit ? p.windGustMPH : p.windGustKPH) }
            if graphWind   { vals.append(useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH) }
        }
        let hi = vals.max() ?? 1
        return 0...(hi + max(1, hi * 0.08))
    }

    /// Whether the current conditions are daytime — drives the sky and the
    /// legible ink for axes/labels over it.
    private var skyIsDay: Bool { (series.first ?? current)?.isDaylight ?? true }
    /// Ink for axis text/legends/titles: black by day, white by night when the
    /// sky is shown; otherwise the system colour (adapts to light/dark mode).
    private var axisInk: Color { graphSky ? (skyIsDay ? .black : .white) : .primary }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack {
                // #8: current-conditions sky behind the scrolling content.
                if graphSky {
                    WeatherSkyView(point: series.first ?? current)
                        .ignoresSafeArea()
                }
                ScrollView {
                if series.isEmpty {
                    ForecastLoadingView(progress: progress, nowTick: nowTick, errorMessage: errorMessage)
                        .padding()
                        .frame(minHeight: h)
                } else if verticalSizeClass == .compact {
                    // iPhone landscape: an optional thin MyFeelsLike strip on
                    // top, the enabled charts side by side below it.
                    VStack(spacing: 8) {
                        ScenarioStrip(activeFeatures: activeFeatures)
                        if colourPanelVisible { myFeelsLikePanel(height: h * 0.16) }
                        HStack(spacing: 12) {
                            if tempPanelVisible { temperatureChart(height: colourPanelVisible ? h * 0.72 : h * 0.9) }
                            if windPanelVisible { precipWindChart(height: colourPanelVisible ? h * 0.72 : h * 0.9) }
                        }
                        if let attribution {
                            WeatherAttributionLink(info: attribution)
                        }
                    }
                    .padding(.horizontal)
                    .frame(minHeight: h)
                } else {
                    let hh = panelHeights(h)
                    VStack(spacing: 8) {
                        ScenarioStrip(activeFeatures: activeFeatures)
                        if tempPanelVisible { temperatureChart(height: hh.temp) }
                        if colourPanelVisible { myFeelsLikePanel(height: hh.colour) }
                        if windPanelVisible { precipWindChart(height: hh.wind) }
                        if let attribution {
                            WeatherAttributionLink(info: attribution)
                        }
                    }
                    .padding(.horizontal)
                    .frame(minHeight: h)
                }
            }
            .refreshable { await onRefresh?() }
            }
        }
    }

    /// A thin horizontal MyFeelsLike colour band across the 24 hours — the 24h
    /// analogue of the 10-day heatmap, but a single row (narrower). Aligned in
    /// time with the temperature chart's plot area via the leading padding.
    @ViewBuilder
    private func myFeelsLikePanel(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MyFeelsLike by hour")
                .font(.caption2).foregroundStyle(axisInk)
                .padding(.leading, 36)
            if hasModel {
                Chart(series) { p in
                    // Reliability shrinks the band vertically toward the centre
                    // line, so uncertain hours read as a thinner stripe.
                    let half = myFeelsLikeReliability(p) / 2
                    RectangleMark(
                        xStart: .value("t0", p.date),
                        xEnd:   .value("t1", p.date.addingTimeInterval(3600)),
                        yStart: .value("y0", 0.5 - half),
                        yEnd:   .value("y1", 0.5 + half)
                    )
                    .foregroundStyle(myFeelsLikeHeatColor(p))
                }
                .chartYScale(domain: 0...1)
                // Reserve the same leading width as the temperature/wind charts
                // (a clear 2-digit y-axis) so the band lines up with them.
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0]) {
                        AxisValueLabel { Text("00").font(.caption).foregroundStyle(.clear) }
                    }
                }
                .chartXAxis(.hidden)
                .ifLet(dateDomain) { view, domain in view.chartXScale(domain: domain) }
                .frame(height: height)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.18))
                    .frame(height: height)
                    .padding(.leading, 36)
                    .overlay(
                        Text("No personalised colour yet")
                            .font(.caption2).foregroundStyle(axisInk)
                    )
            }
        }
    }

    @ViewBuilder
    private func temperatureChart(height: CGFloat) -> some View {
        // Compute the domain once (O(n)); reading it per-point would be O(n²).
        let dom = tempYDomain
        let base = dom.lowerBound
        VStack(alignment: .leading, spacing: 2) {
            // Legend without units — only for the enabled series.
            ChartLegendRow(entries: tempLegendEntries, ink: axisInk)
            .padding(.leading, 36)   // start near the y-axis line, not the y-axis labels

            Chart {
                ForEach(series) { p in
                    let dry = useFahrenheit ? p.temperatureF : p.temperatureC
                    let wet = useFahrenheit ? p.wetBulbF : p.wetBulbC
                    let dew = useFahrenheit ? p.dewPointF : p.dewPointC
                    // Filled bands as explicit ranges (so they don't stack):
                    // red below dew point, green dew→wet bulb, blue wet bulb→dry
                    // bulb. Since dry ≥ wet ≥ dew always, the bands nest cleanly.
                    if graphDewPoint {
                        AreaMark(x: .value("Time", p.date),
                                 yStart: .value("base", base),
                                 yEnd: .value("Dew Point", dew),
                                 series: .value("S", "dew"))
                            .foregroundStyle(.red).interpolationMethod(.linear)
                    }
                    if graphWetBulb {
                        AreaMark(x: .value("Time", p.date),
                                 yStart: .value("Dew Point", dew),
                                 yEnd: .value("Wet Bulb", wet),
                                 series: .value("S", "wet"))
                            .foregroundStyle(.green).interpolationMethod(.linear)
                    }
                    if graphTemp {
                        AreaMark(x: .value("Time", p.date),
                                 yStart: .value("Wet Bulb", wet),
                                 yEnd: .value("Temp", dry),
                                 series: .value("S", "dry"))
                            .foregroundStyle(.blue).interpolationMethod(.linear)
                    }
                    // Personalised feels-like (apparent) stays a line, on top.
                    if graphFeels {
                        LineMark(x: .value("Time", p.date),
                                 y: .value("Apparent",
                                           useFahrenheit ? p.apparentTemperatureF : p.apparentTemperatureC),
                                 series: .value("S", "app"))
                            .foregroundStyle(.purple).interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
                // Prominent "now" dots in the gap left of the forecast curves.
                if let c = current {
                    if graphTemp {
                        PointMark(x: .value("Time", c.date),
                                  y: .value("Temp", useFahrenheit ? c.temperatureF : c.temperatureC))
                            .foregroundStyle(.blue).symbolSize(110)
                    }
                    if graphWetBulb {
                        PointMark(x: .value("Time", c.date),
                                  y: .value("Wet Bulb", useFahrenheit ? c.wetBulbF : c.wetBulbC))
                            .foregroundStyle(.green).symbolSize(110)
                    }
                    if graphDewPoint {
                        PointMark(x: .value("Time", c.date),
                                  y: .value("Dew Point", useFahrenheit ? c.dewPointF : c.dewPointC))
                            .foregroundStyle(.red).symbolSize(110)
                    }
                    if graphFeels {
                        PointMark(x: .value("Time", c.date),
                                  y: .value("Apparent",
                                            useFahrenheit ? c.apparentTemperatureF : c.apparentTemperatureC))
                            .foregroundStyle(.purple).symbolSize(110)
                    }
                }
            }
            // MyFeelsLike colour now lives in its own panel below (see
            // myFeelsLikePanel), matching the 10-day screen's heatmap.
            .chartLegend(.hidden)
            .chartYScale(domain: dom)
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 5)) { _ in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel().font(.caption).foregroundStyle(axisInk)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel(centered: true) {
                        Text(value.as(Date.self).map { hourLabel(for: $0) } ?? "")
                            .font(.caption).foregroundStyle(axisInk)
                    }
                }
            }
            .ifLet(dateDomain) { view, domain in view.chartXScale(domain: domain) }
            // Unit annotation just below the topmost y-axis number, in-plot
            // (so the chart area does not need to shrink to make room).
            .overlay(alignment: .topLeading) {
                Text(useFahrenheit ? "°F" : "°C")
                    .font(.caption2)
                    .foregroundStyle(axisInk)
                    .padding(.leading, 4)
                    .padding(.top, 14)
            }
            .frame(height: height - 20)
        }
    }

    @ViewBuilder
    private func precipWindChart(height: CGFloat) -> some View {
        // Compute the domain once (O(n)); reading it per-point would be O(n²).
        let dom = windYDomain
        let base = dom.lowerBound
        VStack(alignment: .leading, spacing: 2) {
            ChartLegendRow(entries: windLegendEntries, ink: axisInk)
            .padding(.leading, 36)

            Chart {
                ForEach(series) { p in
                    let gust = useFahrenheit ? p.windGustMPH : p.windGustKPH
                    let wind = useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH
                    // Filled areas back→front: gust (faint red) behind wind
                    // (red) behind rain (blue). Explicit ranges from the 0
                    // baseline so they overlap rather than stack.
                    if graphGust {
                        AreaMark(x: .value("Time", p.date),
                                 yStart: .value("base", base),
                                 yEnd: .value("Gust", gust), series: .value("S", "gustA"))
                            .foregroundStyle(.red.opacity(0.12)).interpolationMethod(.linear)
                    }
                    if graphWind {
                        AreaMark(x: .value("Time", p.date),
                                 yStart: .value("base", base),
                                 yEnd: .value("Wind", wind), series: .value("S", "windA"))
                            .foregroundStyle(.red.opacity(0.35)).interpolationMethod(.linear)
                    }
                    if graphPrecip {
                        AreaMark(x: .value("Time", p.date),
                                 yStart: .value("base", base),
                                 yEnd: .value("Precip %", p.precipProbability * 100), series: .value("S", "rainA"))
                            .foregroundStyle(.blue.opacity(0.3)).interpolationMethod(.linear)
                    }
                    // Gust dashed + wind solid lines, on top of the rain area.
                    if graphGust {
                        LineMark(x: .value("Time", p.date),
                                 y: .value("Gust", gust), series: .value("S", "gustL"))
                            .foregroundStyle(.red.opacity(0.7)).interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 2.4, dash: [4, 3]))
                            .symbol(Circle()).symbolSize(0)
                    }
                    if graphWind {
                        LineMark(x: .value("Time", p.date),
                                 y: .value("Wind", wind), series: .value("S", "windL"))
                            .foregroundStyle(.red).interpolationMethod(.linear)
                            .symbol(Circle()).symbolSize(0)
                    }
                }
                // Prominent "now" wind/gust dots (current has no precipitation).
                if let c = current {
                    if graphGust {
                        PointMark(x: .value("Time", c.date),
                                  y: .value("Gust", useFahrenheit ? c.windGustMPH : c.windGustKPH))
                            .foregroundStyle(.red.opacity(0.45)).symbolSize(90)
                    }
                    if graphWind {
                        PointMark(x: .value("Time", c.date),
                                  y: .value("Wind", useFahrenheit ? c.windSpeedMPH : c.windSpeedKPH))
                            .foregroundStyle(.red).symbolSize(90)
                    }
                }
            }
            .chartLegend(.hidden)
            .chartYScale(domain: dom)
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 5)) { _ in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel().font(.caption).foregroundStyle(axisInk)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel(centered: true) {
                        Text(value.as(Date.self).map { hourLabel(for: $0) } ?? "")
                            .font(.caption).foregroundStyle(axisInk)
                    }
                }
            }
            .ifLet(dateDomain) { view, domain in view.chartXScale(domain: domain) }
            .frame(height: height - 20)
        }
    }
}

// MARK: - TenDayView

struct TenDayView: View {
    var series: [ForecastPoint]
    /// Observed past ~24 h, drawn dashed to the left of the forecast.
    var historic: [ForecastPoint] = []
    /// "now" boundary point joining the dashed history to the solid forecast.
    var current: ForecastPoint? = nil
    var progress: LoadProgress = LoadProgress()
    var nowTick: Date = .now
    var errorMessage: String? = nil
    var attribution: WeatherAttributionInfo? = nil
    var onRefresh: (() async -> Void)? = nil
    /// Features currently in the regression model. Used to decide which
    /// scenario adjusters to show. Empty = no model, no chips shown.
    var activeFeatures: Set<Feature> = []
    /// Plain-language reasons there's no personalised model yet (empty when one
    /// exists). Shown on the grey heatmap panel.
    var modelReasons: [String] = []
    /// True when embedded in a fixed-height dashboard pane (iPad): panel
    /// fractions shrink so everything fits without scrolling.
    var fitsPane: Bool = false

    @AppStorage("useFahrenheit") private var useFahrenheit: Bool = true
    @AppStorage(GraphKey.temp)     private var graphTemp     = true
    @AppStorage(GraphKey.wetBulb)  private var graphWetBulb  = true
    @AppStorage(GraphKey.dewPoint) private var graphDewPoint = true
    @AppStorage(GraphKey.feels)    private var graphFeels    = true
    @AppStorage(GraphKey.colour)   private var graphColour   = true
    @AppStorage(GraphKey.precip)   private var graphPrecip   = true
    @AppStorage(GraphKey.wind)     private var graphWind     = true
    @AppStorage(GraphKey.gust)     private var graphGust     = true
    @AppStorage(GraphKey.sky)      private var graphSky      = true
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var tempPanelVisible: Bool { graphTemp || graphWetBulb || graphDewPoint || graphFeels }
    private var colourPanelVisible: Bool { graphColour }
    private var windPanelVisible: Bool { graphPrecip || graphWind || graphGust }

    private func panelHeights(_ h: CGFloat) -> (temp: CGFloat, colour: CGFloat, wind: CGFloat) {
        let wT = tempPanelVisible ? 0.42 : 0
        let wC = colourPanelVisible ? 0.30 : 0
        let wW = windPanelVisible ? 0.32 : 0
        let tot = wT + wC + wW
        guard tot > 0 else { return (0, 0, 0) }
        let usable = h * (fitsPane ? 0.92 : 1.0)
        return (usable * wT / tot, usable * wC / tot, usable * wW / tot)
    }

    private var tempLegendEntries: [(color: Color, label: String, isArea: Bool)] {
        var e: [(color: Color, label: String, isArea: Bool)] = []
        if graphFeels    { e.append((.purple, "MyFeelsLike", false)) }
        if graphTemp     { e.append((.blue,   "Temp",        false)) }
        if graphWetBulb  { e.append((.green,  "Wet Bulb",    false)) }
        if graphDewPoint { e.append((.red,    "Dew Pt",      false)) }
        return e
    }

    private var windLegendEntries: [(color: Color, label: String, isArea: Bool)] {
        var e: [(color: Color, label: String, isArea: Bool)] = []
        if graphPrecip { e.append((.blue, "Precip %", true)) }
        if graphWind   { e.append((.red,  useFahrenheit ? "Wind mph" : "Wind kph", false)) }
        if graphGust   { e.append((.red.opacity(0.5), useFahrenheit ? "Gust mph" : "Gust kph", false)) }
        return e
    }

    /// Whether the forecast carries personalised feels-like scores.
    private var hasModel: Bool {
        allPoints.contains { $0.myFeelsLikeScore != nil }
    }

    /// Historic + "now", used for the dashed past line.
    private var historicPlus: [ForecastPoint] {
        historic + (current.map { [$0] } ?? [])
    }
    /// "now" + forecast, used for the solid future line (joins at "now").
    private var forecastPlus: [ForecastPoint] {
        (current.map { [$0] } ?? []) + series
    }
    /// All plotted points oldest→newest, for the MyFeelsLike colour background.
    private var allPoints: [ForecastPoint] {
        historic + (current.map { [$0] } ?? []) + series
    }

    /// Tight y-range over all temperature curves, used as the explicit scale so
    /// the forecast's filled bands have a defined baseline.
    private var tempYDomain: ClosedRange<Double> {
        var vals: [Double] = []
        for p in allPoints {
            if graphTemp     { vals.append(useFahrenheit ? p.temperatureF : p.temperatureC) }
            if graphWetBulb  { vals.append(useFahrenheit ? p.wetBulbF : p.wetBulbC) }
            if graphDewPoint { vals.append(useFahrenheit ? p.dewPointF : p.dewPointC) }
            if graphFeels    { vals.append(useFahrenheit ? p.apparentTemperatureF : p.apparentTemperatureC) }
        }
        guard let lo = vals.min(), let hi = vals.max() else { return 0...1 }
        let pad = max(1, (hi - lo) * 0.08)
        return (lo - pad)...(hi + pad)
    }

    /// y-range for the precip/wind chart, anchored at 0 for the filled areas.
    private var windYDomain: ClosedRange<Double> {
        var vals: [Double] = []
        for p in historic + series {
            if graphPrecip { vals.append(p.precipProbability * 100) }
            if graphGust   { vals.append(useFahrenheit ? p.windGustMPH : p.windGustKPH) }
            if graphWind   { vals.append(useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH) }
        }
        let hi = vals.max() ?? 1
        return 0...(hi + max(1, hi * 0.08))
    }

    /// Whether the current conditions are daytime — drives the sky and the
    /// legible ink for axes/labels over it.
    private var skyIsDay: Bool { (series.first ?? current)?.isDaylight ?? true }
    /// Ink for axis text/legends/titles: black by day, white by night when the
    /// sky is shown; otherwise the system colour (adapts to light/dark mode).
    private var axisInk: Color { graphSky ? (skyIsDay ? .black : .white) : .primary }
    /// x-position of "now", for the current-time marker line.
    private var nowLineDate: Date? { current?.date ?? series.first?.date }

    private var earliestDate: Date? {
        historic.first?.date ?? current?.date ?? series.first?.date
    }

    private var dateDomain: ClosedRange<Date>? {
        guard let lo = earliestDate, let last = series.last?.date else { return nil }
        return lo...last
    }

    private var startMidnight: Date? {
        guard let first = earliestDate else { return nil }
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: first)
        return first > midnight ? cal.date(byAdding: .day, value: 1, to: midnight) : midnight
    }

    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE"
        return df
    }()

    private static let dayAbbreviations = [
        "Mon": "Mo", "Tue": "Tu", "Wed": "We",
        "Thu": "Th", "Fri": "Fr", "Sat": "Sa", "Sun": "Su"
    ]

    private func dayLabel(for date: Date) -> String {
        guard let start = startMidnight, date >= start,
              Calendar.current.component(.hour, from: date) == 0 else { return "" }
        let key = TenDayView.dayFormatter.string(from: date)
        return TenDayView.dayAbbreviations[key] ?? String(key.prefix(2))
    }

    /// The four temperature lines (temp/wet-bulb/dew/apparent) over a set of
    /// points. `suffix` keeps the historic and forecast series distinct so they
    /// are not connected across the "now" boundary; `dash` nil = solid.
    @ChartContentBuilder
    private func tempLines(_ pts: [ForecastPoint], suffix: String, dash: [CGFloat]?) -> some ChartContent {
        ForEach(pts) { p in
            if graphTemp {
                LineMark(x: .value("Time", p.date),
                         y: .value("Temp", useFahrenheit ? p.temperatureF : p.temperatureC),
                         series: .value("S", "A" + suffix))
                    .foregroundStyle(.blue).interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: dash ?? []))
            }
            if graphWetBulb {
                LineMark(x: .value("Time", p.date),
                         y: .value("Wet Bulb", useFahrenheit ? p.wetBulbF : p.wetBulbC),
                         series: .value("S", "B" + suffix))
                    .foregroundStyle(.green).interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: dash ?? []))
            }
            if graphDewPoint {
                LineMark(x: .value("Time", p.date),
                         y: .value("Dew Point", useFahrenheit ? p.dewPointF : p.dewPointC),
                         series: .value("S", "C" + suffix))
                    .foregroundStyle(.red).interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: dash ?? []))
            }
            if graphFeels {
                LineMark(x: .value("Time", p.date),
                         y: .value("Apparent",
                                   useFahrenheit ? p.apparentTemperatureF : p.apparentTemperatureC),
                         series: .value("S", "D" + suffix))
                    .foregroundStyle(.purple).interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: dash ?? []))
            }
        }
    }

    /// Forecast temperature as filled bands (red below dew point, green
    /// dew→wet bulb, blue wet bulb→dry bulb) with the feels-like line on top.
    /// Explicit ranges so the bands don't stack.
    @ChartContentBuilder
    private func tempAreas(_ pts: [ForecastPoint], base: Double) -> some ChartContent {
        ForEach(pts) { p in
            let dry = useFahrenheit ? p.temperatureF : p.temperatureC
            let wet = useFahrenheit ? p.wetBulbF : p.wetBulbC
            let dew = useFahrenheit ? p.dewPointF : p.dewPointC
            if graphDewPoint {
                AreaMark(x: .value("Time", p.date),
                         yStart: .value("base", base),
                         yEnd: .value("Dew Point", dew), series: .value("S", "dewA"))
                    .foregroundStyle(.red).interpolationMethod(.linear)
            }
            if graphWetBulb {
                AreaMark(x: .value("Time", p.date),
                         yStart: .value("Dew Point", dew),
                         yEnd: .value("Wet Bulb", wet), series: .value("S", "wetA"))
                    .foregroundStyle(.green).interpolationMethod(.linear)
            }
            if graphTemp {
                AreaMark(x: .value("Time", p.date),
                         yStart: .value("Wet Bulb", wet),
                         yEnd: .value("Temp", dry), series: .value("S", "dryA"))
                    .foregroundStyle(.blue).interpolationMethod(.linear)
            }
            if graphFeels {
                LineMark(x: .value("Time", p.date),
                         y: .value("Apparent",
                                   useFahrenheit ? p.apparentTemperatureF : p.apparentTemperatureC),
                         series: .value("S", "appA"))
                    .foregroundStyle(.purple).interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
    }

    /// Gust (always dashed) and wind lines over a set of points. `windDash`
    /// makes the wind line dashed for the historic pass, solid for the forecast.
    @ChartContentBuilder
    private func windLines(_ pts: [ForecastPoint], suffix: String, windDash: [CGFloat]?) -> some ChartContent {
        ForEach(pts) { p in
            if graphGust {
                LineMark(x: .value("Time", p.date),
                         y: .value("Gust", useFahrenheit ? p.windGustMPH : p.windGustKPH),
                         series: .value("S", "G" + suffix))
                    .foregroundStyle(.red.opacity(0.7)).interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, dash: [4, 3]))
                    .symbol(Circle()).symbolSize(0)
            }
            if graphWind {
                LineMark(x: .value("Time", p.date),
                         y: .value("Wind", useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH),
                         series: .value("S", "W" + suffix))
                    .foregroundStyle(.red).interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: windDash ?? []))
                    .symbol(Circle()).symbolSize(0)
            }
        }
    }

    /// Feels-like heatmap: one column per day, hour-of-day on the y-axis, cell
    /// colour = personalised feels-like. Separated from the temperature curves
    /// so day-to-day and time-of-day patterns are legible (the curves' x-axis
    /// is time; this grid's y-axis is hour-of-day).
    @ViewBuilder
    private func feelsLikeHeatmap(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MyFeelsLike by time of day")
                .font(.caption2).foregroundStyle(axisInk)
                .padding(.leading, 36)
            if hasModel {
                heatmapChart.frame(height: height - 16)
            } else {
                noModelPanel.frame(height: height - 16)
            }
        }
    }

    private var heatmapChart: some View {
        let cal = Calendar.current
        return Chart(allPoints) { p in
            let dayStart = cal.startOfDay(for: p.date)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let hour = cal.component(.hour, from: p.date)
            // Reliability shrinks the cell horizontally toward the centre of
            // its day column, so uncertain hours read as a narrow sliver.
            let full = dayEnd.timeIntervalSince(dayStart)
            let mid = dayStart.addingTimeInterval(full / 2)
            let half = full / 2 * myFeelsLikeReliability(p)
            RectangleMark(
                xStart: .value("Day", mid.addingTimeInterval(-half)),
                xEnd:   .value("Day end", mid.addingTimeInterval(half)),
                yStart: .value("Hour", hour),
                yEnd:   .value("Hour end", hour + 1)
            )
            .foregroundStyle(myFeelsLikeHeatColor(p))
        }
        .chartYScale(domain: 0...24)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 6, 12, 18]) { v in
                AxisValueLabel {
                    Text(String(format: "%02d", v.as(Int.self) ?? 0))
                        .font(.caption2).foregroundStyle(axisInk)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 1)) { value in
                AxisValueLabel {
                    Text(value.as(Date.self).map { dayLabel(for: $0) } ?? "")
                        .font(.caption).foregroundStyle(axisInk)
                }
            }
        }
    }

    /// Grey panel shown in place of the heatmap until a personalised model
    /// exists, explaining why (with quantities where possible).
    private var noModelPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.18))
            VStack(alignment: .leading, spacing: 6) {
                Text("No personalised feels-like colour yet")
                    .font(.caption.weight(.semibold))
                if modelReasons.isEmpty {
                    Text("Building your model…")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    ForEach(modelReasons, id: \.self) { reason in
                        Text("• " + reason)
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }


    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack {
                // #8: current-conditions sky behind the scrolling content.
                if graphSky {
                    WeatherSkyView(point: series.first ?? current)
                        .ignoresSafeArea()
                }
                ScrollView {
                if series.isEmpty {
                    ForecastLoadingView(progress: progress, nowTick: nowTick, errorMessage: errorMessage)
                        .padding()
                        .frame(minHeight: h)
                } else if verticalSizeClass == .compact {
                    // iPhone landscape: the enabled panels side by side.
                    VStack(spacing: 8) {
                        ScenarioStrip(activeFeatures: activeFeatures)
                        HStack(spacing: 12) {
                            if tempPanelVisible { temperatureChart(height: h * 0.9) }
                            if colourPanelVisible { feelsLikeHeatmap(height: h * 0.9) }
                            if windPanelVisible { precipWindChart(height: h * 0.9) }
                        }
                        if let attribution {
                            WeatherAttributionLink(info: attribution)
                        }
                    }
                    .padding(.horizontal)
                    .frame(minHeight: h)
                } else {
                    let hh = panelHeights(h)
                    VStack(spacing: 8) {
                        ScenarioStrip(activeFeatures: activeFeatures)
                        if tempPanelVisible { temperatureChart(height: hh.temp) }
                        if colourPanelVisible { feelsLikeHeatmap(height: hh.colour) }
                        if windPanelVisible { precipWindChart(height: hh.wind) }
                        if let attribution {
                            WeatherAttributionLink(info: attribution)
                        }
                    }
                    .padding(.horizontal)
                    .frame(minHeight: h)
                }
            }
            .refreshable { await onRefresh?() }
            }
        }
    }

    @ViewBuilder
    private func temperatureChart(height: CGFloat) -> some View {
        // Compute the domain once (O(n)) — reading it inside a per-point
        // ForEach would make it O(n²) and stall scrolling/swiping.
        let dom = tempYDomain
        VStack(alignment: .leading, spacing: 2) {
            // Legend without units — only for the enabled series.
            ChartLegendRow(entries: tempLegendEntries, ink: axisInk)
            .padding(.leading, 36)

            Chart {
                // Past as dashed lines (historic → now); future as filled bands
                // (now → forecast). They share the "now" point at the boundary.
                tempLines(historicPlus, suffix: "h", dash: [4, 3])
                tempAreas(forecastPlus, base: dom.lowerBound)
            }
            .chartLegend(.hidden)
            .chartYScale(domain: dom)
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 5)) { _ in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel().font(.caption).foregroundStyle(axisInk)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 1)) { value in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel {
                        Text(value.as(Date.self).map { dayLabel(for: $0) } ?? "")
                            .font(.caption).foregroundStyle(axisInk)
                    }
                }
            }
            .ifLet(dateDomain) { view, domain in view.chartXScale(domain: domain) }
            // Unit annotation just below the topmost y-axis number.
            .overlay(alignment: .topLeading) {
                Text(useFahrenheit ? "°F" : "°C")
                    .font(.caption2)
                    .foregroundStyle(axisInk)
                    .padding(.leading, 4)
                    .padding(.top, 14)
            }
            .frame(height: height - 20)
        }
    }

    @ViewBuilder
    private func precipWindChart(height: CGFloat) -> some View {
        // Compute the domain once (O(n)); reading it per-point would be O(n²).
        let dom = windYDomain
        let base = dom.lowerBound
        let windPts = historic + series
        VStack(alignment: .leading, spacing: 2) {
            ChartLegendRow(entries: windLegendEntries, ink: axisInk)
            .padding(.leading, 36)

            Chart {
                // Filled areas back→front over history + forecast: gust (faint
                // red) behind wind (red) behind rain (blue). Explicit ranges
                // from the 0 baseline so they overlap rather than stack.
                ForEach(windPts) { p in
                    let gust = useFahrenheit ? p.windGustMPH : p.windGustKPH
                    let wind = useFahrenheit ? p.windSpeedMPH : p.windSpeedKPH
                    if graphGust {
                        AreaMark(x: .value("Time", p.date),
                                 yStart: .value("base", base),
                                 yEnd: .value("Gust", gust), series: .value("S", "gustA"))
                            .foregroundStyle(.red.opacity(0.12)).interpolationMethod(.linear)
                    }
                    if graphWind {
                        AreaMark(x: .value("Time", p.date),
                                 yStart: .value("base", base),
                                 yEnd: .value("Wind", wind), series: .value("S", "windA"))
                            .foregroundStyle(.red.opacity(0.35)).interpolationMethod(.linear)
                    }
                    if graphPrecip {
                        AreaMark(x: .value("Time", p.date),
                                 yStart: .value("base", base),
                                 yEnd: .value("Precip %", p.precipProbability * 100), series: .value("S", "rainA"))
                            .foregroundStyle(.blue.opacity(0.3)).interpolationMethod(.linear)
                    }
                }
                // Wind/gust curves: dashed past, solid future, joined at "now".
                windLines(historicPlus, suffix: "h", windDash: [4, 3])
                windLines(forecastPlus, suffix: "",  windDash: nil)
            }
            .chartLegend(.hidden)
            .chartYScale(domain: dom)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel().font(.caption).foregroundStyle(axisInk)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 1)) { value in
                    AxisGridLine().foregroundStyle(axisInk.opacity(0.25))
                    AxisTick().foregroundStyle(axisInk.opacity(0.6))
                    AxisValueLabel {
                        Text(value.as(Date.self).map { dayLabel(for: $0) } ?? "")
                            .font(.caption).foregroundStyle(axisInk)
                    }
                }
            }
            .ifLet(dateDomain) { view, domain in view.chartXScale(domain: domain) }
            .frame(height: height - 20)
        }
    }
}

// MARK: - Personalised colour background for the temperature chart

/// Cell colour for the MyFeelsLike panels (24h strip + 10-day heatmap): the
/// score's colour at full opacity. Reliability is conveyed by the cell's
/// width (see myFeelsLikeReliability), not by fading. Grey when no score.
func myFeelsLikeHeatColor(_ p: ForecastPoint) -> Color {
    guard let s = p.myFeelsLikeScore else { return Color.gray.opacity(0.25) }
    return ColorScale.color(forScore: s)
}

/// Prediction reliability in 0…1, used to scale a cell's width so uncertain
/// forecasts read as a thinner band rather than a fainter colour. A small
/// floor keeps even the least reliable cell visible as a sliver.
func myFeelsLikeReliability(_ p: ForecastPoint) -> Double {
    guard p.myFeelsLikeScore != nil else { return 1 }
    return max(0.15, min(1, p.myFeelsLikeOpacity))
}


// MARK: - Solid-run tagging for the MyFeelsLike chart line (legacy, unused)

#if false
private struct TaggedPoint: Identifiable {
    var id: UUID { base.id }
    let base: ForecastPoint
    let solidRunID: Int?
}

/// Assigns each contiguous run of w==0 points a unique integer run ID.
private func tagSolidRuns(_ pts: [ForecastPoint]) -> [TaggedPoint] {
    var out: [TaggedPoint] = []
    var runID = 0
    var prevWasBlended = true
    for p in pts {
        if p.myFeelsLikeApparentWeight == 0 {
            if prevWasBlended { runID += 1 }   // new run starts
            out.append(TaggedPoint(base: p, solidRunID: runID))
            prevWasBlended = false
        } else {
            out.append(TaggedPoint(base: p, solidRunID: nil))
            prevWasBlended = true
        }
    }
    return out
}
#endif

// MARK: - Indoor (evaporative cooler) controls — currently disabled

#if false
struct IndoorControlsView: View {
    @Binding var insulation: Double
    @AppStorage("fanEnabled") private var fanEnabled: Bool = false
    @AppStorage("fanWindKPH") private var fanWindKPH: Double = 10
    @AppStorage("useFahrenheit") private var useFahrenheit: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("House insulation").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(insulation.rounded()))%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $insulation, in: 0...100, step: 1)
                Text("0 = indoor ≈ outdoor air   ·   100 = cools to wet-bulb")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $fanEnabled) {
                Text("Fan").font(.subheadline.weight(.semibold))
            }

            if fanEnabled {
                let unit  = useFahrenheit ? "mph" : "kph"
                let shown = useFahrenheit ? fanWindKPH / 1.609344 : fanWindKPH
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Fan air speed").font(.caption)
                        Spacer()
                        Text(String(format: "%.0f %@", shown, unit))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $fanWindKPH, in: 0...40, step: 1)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}
#endif

// MARK: - View extension

private extension View {
    @ViewBuilder
    func ifLet<T, Content: View>(_ value: T?, transform: (Self, T) -> Content) -> some View {
        if let v = value { transform(self, v) } else { self }
    }
}

#Preview {
    ContentView()
}
