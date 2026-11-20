//
//  Item.swift
//  WeightControlApp
//
//  Created by 金丸悠汰 on 2026/11/20.
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
