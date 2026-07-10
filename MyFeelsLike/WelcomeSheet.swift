// SPDX-License-Identifier: GPL-3.0-or-later
//
//  WelcomeSheet.swift
//  MyFeelsLike
//
//  Shown once on first launch, and again after an update, so people meet the
//  app (and can jump straight to the Info screen) without hunting through
//  Settings. Which one is shown depends on whether a version was seen before.
//

import SwiftUI

enum AppVersion {
    /// Marketing version, e.g. "1.0".
    static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// One-line summary shown after an update. Edit this per release.
    static let whatsNew =
        "Compare your MyFeelsLike with people nearby, see in-sun vs in-shade in the color band, and read the day's range on the watch complication."
}

struct WelcomeSheet: View {
    /// False on a first install, true when the app has been updated.
    let isUpdate: Bool
    /// Called (after this sheet closes) when the user wants the Info screen.
    let onReadGuide: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "thermometer.sun.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .padding(.top, 8)

            Text(isUpdate ? "What's new" : "Welcome to MyFeelsLike")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(isUpdate ? AppVersion.whatsNew : Self.introduction)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button { onReadGuide(); dismiss() } label: {
                    Text("Read the guide").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("Got it") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .presentationDetents([.medium])
    }

    private static let introduction = """
    MyFeelsLike learns how the weather actually feels to you. Rate a few \
    moments and the forecast is colored by your own comfort — no degrees \
    needed. Colors appear once you've given about five ratings.
    """
}

#Preview {
    WelcomeSheet(isUpdate: false, onReadGuide: {})
}
