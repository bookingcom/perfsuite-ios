//
//  DispatchTimeInterval+Helpers.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 07/07/2021.
//

import Foundation

public extension DispatchTimeInterval {


    /// Initializer to create a zero interval.
    static var zero: DispatchTimeInterval {
        return .seconds(0)
    }

    /// Helper method to get TimeInterval (Double) number of seconds from `DispatchTimeInterval`.
    var timeInterval: TimeInterval? {
        switch self {
        case let .seconds(seconds):
            return TimeInterval(seconds)
        case let .milliseconds(milliseconds):
            return TimeInterval(milliseconds) / 1000
        case let .microseconds(microseconds):
            return TimeInterval(microseconds) / 1000_000
        case let .nanoseconds(nanoseconds):
            return TimeInterval(nanoseconds) / 1000_000_000
        case .never:
            return nil
        @unknown default:
            return nil
        }
    }

    /// Helper method to get Int number of seconds from `DispatchTimeInterval`.
    ///
    /// Use it if you have so large amount of seconds, which won't fit into Int with the better precision.
    var seconds: Int? {
        switch self {
        case let .seconds(seconds):
            return seconds
        case let .milliseconds(milliseconds):
            return milliseconds / 1000
        case let .microseconds(microseconds):
            return microseconds / 1000_000
        case let .nanoseconds(nanoseconds):
            return nanoseconds / 1000_000_000
        case .never:
            return nil
        @unknown default:
            return nil
        }
    }

    /// Helper method to get Int number of milliseconds from `DispatchTimeInterval`.
    ///
    /// Use it if you don't need nanoseconds or microseconds precision.
    ///
    /// ## Caution!
    /// Number of milliseconds may not fit into `Int` if we have large amount of seconds in the enum. We return `nil` in this case.
    var milliseconds: Int? {
        switch self {
        case let .seconds(seconds):
            return handleOverflow(seconds.multipliedReportingOverflow(by: 1000))
        case let .milliseconds(milliseconds):
            return milliseconds
        case let .microseconds(microseconds):
            return microseconds / 1000
        case let .nanoseconds(nanoseconds):
            return nanoseconds / 1000_000
        case .never:
            return nil
        @unknown default:
            return nil
        }
    }

    /// Helper method to get Int number of milliseconds from `DispatchTimeInterval`.
    ///
    /// Use it if you don't need microseconds precision.
    ///
    /// ## Caution!
    /// Number of microseconds may not fit into `Int` if we have large amount of seconds in the enum. We return `nil` in this case.
    var microseconds: Int? {
        switch self {
        case let .seconds(seconds):
            return handleOverflow(seconds.multipliedReportingOverflow(by: 1000_000))
        case let .milliseconds(milliseconds):
            return handleOverflow(milliseconds.multipliedReportingOverflow(by: 1000))
        case let .microseconds(microseconds):
            return microseconds
        case let .nanoseconds(nanoseconds):
            return nanoseconds / 1000
        case .never:
            return nil
        @unknown default:
            return nil
        }
    }

    /// Helper method to get Int number of nanoseconds from `DispatchTimeInterval`.
    ///
    /// ## Caution!
    /// Number of nanoseconds may not fit into `Int` if we have large amount of seconds in the enum. We return `nil` in this case.
    var nanoseconds: Int? {
        switch self {
        case let .seconds(seconds):
            return handleOverflow(seconds.multipliedReportingOverflow(by: 1000_000_000))
        case let .milliseconds(milliseconds):
            return handleOverflow(milliseconds.multipliedReportingOverflow(by: 1000_000))
        case let .microseconds(microseconds):
            return handleOverflow(microseconds.multipliedReportingOverflow(by: 1000))
        case let .nanoseconds(nanoseconds):
            return nanoseconds
        case .never:
            return nil
        @unknown default:
            return nil
        }
    }

    /// Initializer with `TimeInterval` amount of seconds.
    /// It uses the best possible precision. If `interval` doesn't fit even with `seconds` precision, we will return `.never`.
    static func timeInterval(_ interval: TimeInterval) -> DispatchTimeInterval {
        if let nanoseconds = Int(exactly: floor(interval * 1_000_000_000)) {
            return .nanoseconds(nanoseconds)
        } else if let microseconds = Int(exactly: floor(interval * 1_000_000)) {
            return .microseconds(microseconds)
        } else if let milliseconds = Int(exactly: floor(interval * 1_000)) {
            return .milliseconds(milliseconds)
        } else if let seconds = Int(exactly: floor(interval)) {
            return .seconds(seconds)
        } else {
            return .never
        }
    }

    private static func tryPrecision(lhs: DispatchTimeInterval, rhs: DispatchTimeInterval, precision: KeyPath<DispatchTimeInterval, Int?>, result: (Int) -> DispatchTimeInterval) -> DispatchTimeInterval? {
        guard let llhs = lhs[keyPath: precision], let rrhs = rhs[keyPath: precision] else {
            return nil
        }

        guard let resultValue = handleOverflow(llhs.addingReportingOverflow(rrhs)) else {
            return nil
        }
        return result(resultValue)
    }

    private static func sumUsingTheBestPrecision(lhs: DispatchTimeInterval, rhs: DispatchTimeInterval, precision: DispatchTimeInterval)
    -> DispatchTimeInterval {
        var (tryNanoseconds, tryMicroseconds, tryMilliseconds, trySeconds) = (false, false, false, false)
        switch precision {
        case .nanoseconds:
            (tryNanoseconds, tryMicroseconds, tryMilliseconds, trySeconds) = (true, true, true, true)
        case .microseconds:
            (tryMicroseconds, tryMilliseconds, trySeconds) = (true, true, true)
        case .milliseconds:
            (tryMilliseconds, trySeconds) = (true, true)
        case .seconds:
            trySeconds = true
        case .never:
            break
        @unknown default:
            break
        }

        if tryNanoseconds, let result = tryPrecision(lhs: lhs, rhs: rhs, precision: \.nanoseconds, result: DispatchTimeInterval.nanoseconds) {
            return result
        }

        if tryMicroseconds, let result = tryPrecision(lhs: lhs, rhs: rhs, precision: \.microseconds, result: DispatchTimeInterval.microseconds) {
            return result
        }

        if tryMilliseconds, let result = tryPrecision(lhs: lhs, rhs: rhs, precision: \.milliseconds, result: DispatchTimeInterval.milliseconds) {
            return result
        }

        if trySeconds, let result = tryPrecision(lhs: lhs, rhs: rhs, precision: \.seconds, result: DispatchTimeInterval.seconds) {
            return result
        }

        return .never
    }

    /// Adding ability to sum up 2 DispatchTimeInterval
    /// We need it to measure `freezeTime`.
    ///
    /// ## Caution!
    /// Sum for the seconds might not fit into `Int`, we will return `.never` in this case.
    static func + (_ lhs: DispatchTimeInterval, _ rhs: DispatchTimeInterval) -> DispatchTimeInterval {
        /// We try to sum up 2 DispatchTimeInterval with the precision passed in `precision` variable. If it doesn't fit into `Int` - we move to the less precision and try it too.

        switch (lhs, rhs) {
        case (.never, _), (_, .never):
            return .never
            // If we have the same precision for both addends - we use the same precision for the sum.
        case let (.nanoseconds(llhs), .nanoseconds(rrhs)):
            return .nanoseconds(llhs + rrhs)
        case let (.microseconds(llhs), .microseconds(rrhs)):
            return .microseconds(llhs + rrhs)
        case let (.milliseconds(llhs), .milliseconds(rrhs)):
            return .milliseconds(llhs + rrhs)
        case let (.seconds(llhs), .seconds(rrhs)):
            return .seconds(llhs + rrhs)
            // If we have the different precision we try to use the more accurate one,
            // and if we don't fit into Integer, moving to the next precision.
        case (.nanoseconds, _), (_, .nanoseconds):
            return sumUsingTheBestPrecision(lhs: lhs, rhs: rhs, precision: .nanoseconds(0))
        case (.microseconds, _), (_, .microseconds):
            return sumUsingTheBestPrecision(lhs: lhs, rhs: rhs, precision: .microseconds(0))
        case (.milliseconds, _), (_, .milliseconds):
            return sumUsingTheBestPrecision(lhs: lhs, rhs: rhs, precision: .milliseconds(0))
        case (.seconds, _), (_, .seconds):
            return sumUsingTheBestPrecision(lhs: lhs, rhs: rhs, precision: .nanoseconds(0))
        default:
            return .never
        }
    }

    /// Adding ability to compare 2 DispatchTimeInterval
    /// We need it to compare `freezeTime` with the threshold.
    static func > (_ lhs: DispatchTimeInterval, _ rhs: DispatchTimeInterval) -> Bool {
        if lhs == rhs {
            return false
        }
        // We try to compare with the most accurate possible precision.
        // If we don't fit into Integer, we are moving to the next precision and try it.
        if let llhs = lhs.nanoseconds, let rrhs = rhs.nanoseconds {
            return llhs > rrhs
        }
        if let llhs = lhs.microseconds, let rrhs = rhs.microseconds {
            return llhs > rrhs
        }
        if let llhs = lhs.milliseconds, let rrhs = rhs.milliseconds {
            return llhs > rrhs
        }
        if let llhs = lhs.seconds, let rrhs = rhs.seconds {
            return llhs > rrhs
        }
        return false
    }

    static func < (_ lhs: DispatchTimeInterval, _ rhs: DispatchTimeInterval) -> Bool {
        if lhs == rhs {
            return false
        }

        return !(lhs > rhs)
    }
}

private func handleOverflow(_ tuple: (partialValue: Int, overflow: Bool)) -> Int? {
    if tuple.overflow {
        return nil
    }

    return tuple.partialValue
}
