//
//  Item.swift
//  MyFeelsLike
//
//  Created by Rob Boer on 5/9/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
