//
//  MeasurementHandle.swift
//  PerformanceSuite
//

import Foundation

/// Opaque handle returned from a receiver's `*Started` callback and passed back to the
/// matching `*Ended`. Lets a receiver carry per-measurement state across the gap. The
/// reporter calls `cancel()` if the measurement is abandoned (screen ignored, deinit
/// before the terminal callback, etc). `cancel()` MUST be safe to call after `*Ended` ran.
public protocol MeasurementHandle: AnyObject {
    func cancel()
}
