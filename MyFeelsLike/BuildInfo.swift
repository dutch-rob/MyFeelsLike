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
    /// compiled executable.
    ///
    /// Not Info.plist: Xcode only rewrites that when something affecting it
    /// changes, so on an incremental build it keeps the date of the last clean
    /// build and the screen shows a stale timestamp. The executable is relinked
    /// whenever any source file changes, which is exactly the event this is
    /// meant to report — and if nothing changed, no relink happens and the old
    /// date is the right answer. Nil if the executable cannot be read.
    static var date: Date? {
        guard let url = Bundle.main.executableURL,
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
