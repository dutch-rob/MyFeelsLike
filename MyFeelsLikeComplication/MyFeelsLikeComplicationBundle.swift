// SPDX-License-Identifier: GPL-3.0-or-later
//
//  MyFeelsLikeComplicationBundle.swift
//  MyFeelsLikeComplication
//
//  Created by Rob Boer on 6/22/26.
//

import WidgetKit
import SwiftUI

@main
struct MyFeelsLikeComplicationBundle: WidgetBundle {
    var body: some Widget {
        MyFeelsLikeComplication()          // corner
        MyFeelsLikeCircularComplication()  // inner circular
    }
}
