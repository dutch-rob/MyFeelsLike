// SPDX-License-Identifier: GPL-3.0-or-later
//
//  BuildInfo.swift
//  MyFeelsLike
//
//  When this copy of the app was built, for telling one TestFlight or
//  development build from another at a glance.
//

import Foundation

enum BuildInfo {

    /// Marketing version and build number, e.g. "1.2 (34)".
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// When the bundle was built, taken from the modification date of the
    /// built Info.plist. Xcode rewrites that file on every build, so it moves
    /// with the build without needing a run-script phase to stamp a date in.
    /// Nil if the bundle has no readable Info.plist.
    static var date: Date? {
        guard let url = Bundle.main.url(forResource: "Info", withExtension: "plist"),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        else { return nil }
        return attrs[.modificationDate] as? Date
    }

    /// "1.2 (34) · 29 Aug 2026, 14:07", or just the version when the build
    /// date cannot be read.
    static var versionAndDate: String {
        guard let date else { return versionString }
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy, HH:mm"
        return "\(versionString) · \(f.string(from: date))"
    }
}
