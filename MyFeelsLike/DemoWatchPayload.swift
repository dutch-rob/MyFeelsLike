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
        "aicc": 84.8864335496692,
        "coefficients": [
          508.06666666666666,
          92.81972905197618,
          68.06026478412802,
          -3.935706207922294
        ],
        "featureRanges": {
          "apparentTempC": {
            "hi": 15.85,
            "lo": 9.04
          },
          "cloudCoverMedium": {
            "hi": 0.93,
            "lo": 0
          },
          "sun": {
            "hi": 1,
            "lo": -1
          }
        },
        "invXtX": [
          [
            0.04166666666666668,
            2.125710688296005e-18,
            -1.6888787644020207e-17,
            4.680176087921392e-18
          ],
          [
            2.1257106882960052e-18,
            0.04525283525208133,
            -0.007472980073076375,
            -0.005515066645261047
          ],
          [
            -1.688878764402021e-17,
            -0.007472980073076375,
            0.04494059850005525,
            0.00406931352353762
          ],
          [
            4.680176087921392e-18,
            -0.005515066645261047,
            0.004069313523537619,
            0.044378656448705964
          ]
        ],
        "lastFitAt": 809920981.198797,
        "means": [
          0,
          11.201666666666666,
          0.33375000000000005
        ],
        "observationRanges": {
          "activity": {
            "hi": 1,
            "lo": 1
          },
          "apparentC": {
            "hi": 15.85,
            "lo": 9.04
          },
          "cloud": {
            "hi": 1,
            "lo": 0
          },
          "cloudHigh": {
            "hi": 1,
            "lo": 0
          },
          "cloudLow": {
            "hi": 0.95,
            "lo": 0
          },
          "cloudMed": {
            "hi": 0.93,
            "lo": 0
          },
          "dewC": {
            "hi": 11.32,
            "lo": 6.15
          },
          "dress": {
            "hi": 0,
            "lo": 0
          },
          "humidity": {
            "hi": 0.95,
            "lo": 0.6
          },
          "precipMM": {
            "hi": 0.89,
            "lo": 0
          },
          "precipProb": {
            "hi": 0.48,
            "lo": 0
          },
          "pressurePa": {
            "hi": 103150.54,
            "lo": 100462.49
          },
          "sun": {
            "hi": 1,
            "lo": -1
          },
          "tempC": {
            "hi": 16.27,
            "lo": 9.83
          },
          "uv": {
            "hi": 2,
            "lo": 0
          },
          "wetBulbC": {
            "hi": 12.29,
            "lo": 8.14
          },
          "windKPH": {
            "hi": 15.06,
            "lo": 6.02
          }
        },
        "rSquared": 0.9984537833152514,
        "ratingCount": 24,
        "scoreRange": {
          "hi": 795,
          "lo": 318.59999999999997
        },
        "selectedFeatures": [
          "sun",
          "apparentTempC",
          "cloudCoverMedium"
        ],
        "stds": [
          0.8340576562282991,
          1.7372758952543732,
          0.32717250469146536
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
