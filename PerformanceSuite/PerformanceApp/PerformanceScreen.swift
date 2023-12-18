//
//  PerformanceScreen.swift
//  PerformanceApp
//
//  Created by Gleb Tarasov on 18/12/2023.
//

import Foundation


/// Every root view should implement this protocol and return an enum value, corresponding to this view
protocol PerformanceTrackable {
    var performanceScreen: PerformanceScreen? { get }
}

enum PerformanceScreen: String {
    case menu
    case rendering
    case list
}
