// SPDX-License-Identifier: GPL-3.0-or-later
//
//  The size of the window itself, which is not something SwiftUI will tell
//  you. A background layer reports the width left after the safe area is taken
//  out, and `ignoresSafeArea()` on it does not change that — so on a foldable,
//  where the status corner is carved out of one side, halving what SwiftUI
//  reports puts the middle several points away from the actual fold.
//
//  Apple's own foldable advice is to read `window.bounds` rather than
//  `UIScreen.main.bounds`, which is what this does.

import SwiftUI
import UIKit

struct WindowSizeReader: UIViewRepresentable {
    var onChange: (CGSize) -> Void

    final class ReportingView: UIView {
        var onChange: ((CGSize) -> Void)?
        private var last: CGSize = .zero

        private func report() {
            guard let size = window?.bounds.size, size != last else { return }
            last = size
            onChange?(size)
        }
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        override func layoutSubviews() { super.layoutSubviews(); report() }
    }

    func makeUIView(context: Context) -> ReportingView {
        let view = ReportingView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ReportingView, context: Context) {
        uiView.onChange = onChange
    }
}
