//
//  ScenarioStripTests.swift
//  MyFeelsLikeTests
//
//  ScenarioStrip decides, per scenario option, whether enough ratings exist
//  for the model to be informative at that level and grays the option out
//  if not. A wrong count wouldn't crash or look obviously broken — it would
//  just silently let the user pick an under-sampled option (or block a
//  well-sampled one), the same "invisible" failure class as the rating
//  color-scroll bug (see ColorScoreColumnTests).
//

import Testing
@testable import MyFeelsLike

struct ScenarioStripTests {

    // MARK: - shows(_:activeFeatures:)

    @Test func nilActiveFeaturesShowsEveryChip() {
        #expect(ScenarioStrip.shows(.activity, activeFeatures: nil))
        #expect(ScenarioStrip.shows(.dress,    activeFeatures: nil))
        #expect(ScenarioStrip.shows(.sun,      activeFeatures: nil))
    }

    @Test func activeFeaturesRestrictsToChipsInTheModel() {
        let active: Set<Feature> = [.activity, .sun]
        #expect(ScenarioStrip.shows(.activity, activeFeatures: active))
        #expect(!ScenarioStrip.shows(.dress, activeFeatures: active))
        #expect(ScenarioStrip.shows(.sun, activeFeatures: active))
    }

    // MARK: - count(feature:value:in:)

    @Test func countMatchesOnlyTheRequestedFeatureAndValue() {
        let ratings = [
            mkRating(apparent: 20, activity: 1, dress: 0,  sun: 1,  feelsLike: 500),
            mkRating(apparent: 20, activity: 1, dress: -1, sun: 1,  feelsLike: 500),
            mkRating(apparent: 20, activity: 2, dress: 0,  sun: -1, feelsLike: 500),
        ]
        #expect(ScenarioStrip.count(feature: .activity, value: 1, in: ratings) == 2)
        #expect(ScenarioStrip.count(feature: .activity, value: 2, in: ratings) == 1)
        #expect(ScenarioStrip.count(feature: .activity, value: 3, in: ratings) == 0)
        #expect(ScenarioStrip.count(feature: .dress, value: 0, in: ratings) == 2)
        #expect(ScenarioStrip.count(feature: .sun, value: 1, in: ratings) == 2)
        // A feature this function doesn't handle (e.g. a continuous weather
        // feature) must count as zero, never silently match everything.
        #expect(ScenarioStrip.count(feature: .apparentTempC, value: 1, in: ratings) == 0)
    }

    @Test func countOfEmptyRatingsIsZero() {
        #expect(ScenarioStrip.count(feature: .activity, value: 1, in: []) == 0)
    }

    // MARK: - isUnderSampled(count:) — the enable/disable boundary

    @Test func exactlyAtThresholdIsNotUnderSampled() {
        #expect(!ScenarioStrip.isUnderSampled(count: ScenarioStrip.minObservations))
    }

    @Test func oneBelowThresholdIsUnderSampled() {
        #expect(ScenarioStrip.isUnderSampled(count: ScenarioStrip.minObservations - 1))
    }

    @Test func wellAboveThresholdIsNotUnderSampled() {
        #expect(!ScenarioStrip.isUnderSampled(count: ScenarioStrip.minObservations + 10))
    }

    // MARK: - displayLabel / currentLabel

    @Test func displayLabelAddsCountHintOnlyWhenDisabled() {
        #expect(ScenarioStrip.displayLabel("Light", n: 2, disabled: true) == "Light  ·  2 rated")
        #expect(ScenarioStrip.displayLabel("Light", n: 9, disabled: false) == "Light")
    }

    @Test func currentLabelFindsMatchingOptionOrFallsBackToQuestionMark() {
        let options = [(0, "—"), (1, "Light"), (2, "Moderate")]
        #expect(ScenarioStrip.currentLabel(for: 1, in: options) == "Light")
        #expect(ScenarioStrip.currentLabel(for: 99, in: options) == "?")
    }
}
