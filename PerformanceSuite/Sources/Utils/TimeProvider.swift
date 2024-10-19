//
//  TimeProvider.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 25/01/2022.
//

import Foundation

protocol TimeProvider {
    func now() -> DispatchTime
}

/// This is `var` only for tests. Shouldn't be changed in production.
var defaultTimeProvider: TimeProvider = DefaultTimeProvider()

final class DefaultTimeProvider: TimeProvider {
    func now() -> DispatchTime {
        return DispatchTime.now()
    }
}
