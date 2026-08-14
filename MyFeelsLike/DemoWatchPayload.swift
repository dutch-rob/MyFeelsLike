// SPDX-License-Identifier: GPL-3.0-or-later
//
//  DemoWatchPayload.swift
//  MyFeelsLike  (shared: iOS app + watch app)
//
//  Screenshot mode on the watch. The watch has no ratings store and no
//  regression code — normally its model arrives from the phone over
//  WatchConnectivity. For App Store screenshots we can't depend on a paired
//  phone and a delivered sync, so the demo model is embedded here, encoded
//  exactly as the phone would have sent it.
//
//  Regenerate with MyFeelsLikeTests/DemoWatchPayloadTests (testPrintFreshPayload).
//  A companion test fails if the model-selection rules drift away from this
//  copy, which would otherwise leave the watch screenshots colored differently
//  from the phone's.
//

import Foundation

enum DemoWatchPayload {
    static let json = #"""
    {
      "places": [],
      "regressionState": {
        "aicc": -418.6901891467042,
        "coefficients": [
          474.19999999999993,
          38.29271872944392
        ],
        "featureRanges": {
          "apparentTempC": {
            "hi": 14.1,
            "lo": 10.83
          }
        },
        "invXtX": [
          [
            0.07142857142857144,
            -5.856121448572256e-17
          ],
          [
            -5.856121448572256e-17,
            0.07692307692307693
          ]
        ],
        "lastFitAt": 808418091.358031,
        "means": [
          12.155
        ],
        "observationRanges": {
          "activity": {
            "hi": 1,
            "lo": 1
          },
          "apparentC": {
            "hi": 14.1,
            "lo": 10.83
          },
          "cloud": {
            "hi": 0.98,
            "lo": 0
          },
          "cloudHigh": {
            "hi": 1,
            "lo": 0
          },
          "cloudLow": {
            "hi": 0.56,
            "lo": 0
          },
          "cloudMed": {
            "hi": 0.8,
            "lo": 0
          },
          "dewC": {
            "hi": 11.27,
            "lo": 6.49
          },
          "dress": {
            "hi": 0,
            "lo": 0
          },
          "humidity": {
            "hi": 0.88,
            "lo": 0.62
          },
          "precipMM": {
            "hi": 0.47,
            "lo": 0
          },
          "precipProb": {
            "hi": 0.42,
            "lo": 0
          },
          "pressurePa": {
            "hi": 103132.46,
            "lo": 100810.08
          },
          "sun": {
            "hi": 1,
            "lo": -1
          },
          "tempC": {
            "hi": 15.61,
            "lo": 9.68
          },
          "uv": {
            "hi": 3,
            "lo": 0
          },
          "wetBulbC": {
            "hi": 12.37,
            "lo": 8.09
          },
          "windKPH": {
            "hi": 15.76,
            "lo": 5.76
          }
        },
        "rSquared": 1,
        "ratingCount": 14,
        "scoreRange": {
          "hi": 552,
          "lo": 421.2
        },
        "selectedFeatures": [
          "apparentTempC"
        ],
        "stds": [
          0.9573179682360987
        ]
      },
      "scenarioActivity": 1,
      "scenarioDress": 0,
      "scenarioSun": 0,
      "useFahrenheit": false
    }
    """#

    /// The demo model + settings, or nil if the embedded JSON is unreadable.
    static var payload: WatchSyncPayload? {
        try? JSONDecoder().decode(WatchSyncPayload.self, from: Data(json.utf8))
    }

    /// The place name the demo forecast belongs to, shown instead of
    /// "Current Location".
    static var place: PlaceDTO {
        PlaceDTO(id: UUID(uuidString: "00000000-0000-0000-0000-0000000DEM0") ?? UUID(),
                 name: DemoMode.placeName,
                 latitude: -34.9285, longitude: 138.6007, altitude: 50)
    }
}
