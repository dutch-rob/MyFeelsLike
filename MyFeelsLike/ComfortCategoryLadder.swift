// SPDX-License-Identifier: GPL-3.0-or-later
//
//  ComfortCategoryLadder.swift
//  MyFeelsLike
//
//  The comfort scale said in words instead of colors, for "No color" mode.
//
//  A zigzag line runs the length of the scale, touching one edge at each named
//  category and the opposite edge at the next. Where the line is hard against
//  an edge, that category is the whole reading; on the slopes between, the two
//  neighbours share the width in proportion — so the drawing carries the
//  gradual transition that a color gradient carries by blending hues, without
//  using hue for anything.
//

import SwiftUI

struct ComfortCategoryLadder: View {
    /// Score at the top of the drawn region, and at the bottom. The rating
    /// column runs hot (1000) at the top down to cold (0) at the bottom.
    var topScore: Double = ColorScale.maxScore
    var bottomScore: Double = ColorScale.minScore
    /// Inset of the drawn scale from the top of the view, and its length.
    /// Lets the caller line the ladder up with a scrolling ruler.
    var activeTop: CGFloat = 0
    var activeSpan: CGFloat? = nil

    var body: some View {
        Canvas { ctx, size in
            let span = activeSpan ?? size.height
            guard span > 0, size.width > 0, topScore != bottomScore else { return }

            func y(_ score: Double) -> CGFloat {
                let f = (score - bottomScore) / (topScore - bottomScore)
                return activeTop + span * (1 - CGFloat(f))
            }

            let inset: CGFloat = 2
            let left = inset, right = size.width - inset
            let cats = ColorScale.comfortCategories          // cold → hot

            // Alternate which edge the line touches, so each category gets a
            // clear side of its own to be labelled in.
            func edge(_ i: Int) -> CGFloat { i.isMultiple(of: 2) ? left : right }

            var path = Path()
            for (i, c) in cats.enumerated() {
                let pt = CGPoint(x: edge(i), y: y(c.score))
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            ctx.stroke(path, with: .color(.primary), lineWidth: 1.5)

            // Each label sits opposite the edge its category's vertex touches —
            // in the open space the zigzag leaves for it.
            for (i, c) in cats.enumerated() {
                let onLeft = !i.isMultiple(of: 2)
                // Turned to run along the column instead of across it. The
                // column is tall and narrow, so horizontal text had only its
                // width to work with and had to stay small; rotated, the names
                // have the whole height and can be read at a usable size.
                var text = ctx.resolve(Text(c.name).font(.system(size: 17, weight: .semibold)))
                text.shading = .color(.primary)
                let tSize = text.measure(in: size)
                let x = onLeft ? left + 4 + tSize.height / 2 : right - 4 - tSize.height / 2
                let at = CGPoint(x: x, y: y(c.score))
                ctx.drawLayer { layer in
                    layer.translateBy(x: at.x, y: at.y)
                    layer.rotate(by: .degrees(-90))
                    // A chip behind the word: the selection indicator sweeps
                    // across the column and crosses each label exactly when
                    // that category is the one being chosen, which is the worst
                    // moment for it to be washed out.
                    let chip = CGRect(x: -tSize.width / 2 - 4, y: -tSize.height / 2 - 2,
                                      width: tSize.width + 8, height: tSize.height + 4)
                    layer.fill(Path(roundedRect: chip, cornerRadius: 3),
                               with: .color(Color(uiColor: .secondarySystemBackground)))
                    layer.draw(text, at: .zero, anchor: .center)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
        .accessibilityLabel("Comfort scale from very cold at the bottom to hot at the top")
    }
}
