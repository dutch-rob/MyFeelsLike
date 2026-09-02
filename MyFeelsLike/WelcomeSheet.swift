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
    static let whatsNew = """
        Options for color vision deficiency: a red-free scale, and a no-color \
        scale that names the comfort categories instead.

        The color scale is brighter through the change from blue to green, \
        which used to darken there. Blue, green and yellow have not moved, so \
        a rating still means what it did.
        """
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
