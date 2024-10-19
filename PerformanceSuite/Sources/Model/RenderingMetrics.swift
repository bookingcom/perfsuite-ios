//
//  RenderingMetrics.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 26/01/2022.
//

import Foundation

/// Continuous data that we gather about the rendering performance
public struct RenderingMetrics: CustomStringConvertible, Equatable {

    private static let slowFrameThreshold: CFTimeInterval = 0.017
    private static let frozenFrameThreshold: CFTimeInterval = 0.7
    static let refreshRateDurationThreshold: CFTimeInterval = 0.001

    /// Total amount of frames rendered.
    public let renderedFrames: Int

    /// Expected amount of frames rendered if everything renders without any delay.
    /// This `expectedFrames` is equal to `renderedFrames` if `droppedFrames` is 0.
    public let expectedFrames: Int

    /// Number of frames which were skipped because the main thread was busy with some work.
    ///
    /// In the ideal performant app `droppedFrames` should always be 0.
    ///
    /// For example, if the device usually displays 60 frames per second,
    /// having 120 dropped frames will mean there was a 2 seconds freeze in total.
    public let droppedFrames: Int

    /// Total amount of frozen frames during view controller appearance.
    ///
    /// Frozen frame is frame that takes at least 700ms to render.
    /// It is a term from [Android development](https://developer.android.com/topic/performance/vitals/frozen).
    public let frozenFrames: Int

    /// Total amount of slow frames during view controller appearance.
    ///
    /// Slow frame is frame that takes at least 17ms to render.
    /// It is a term from [Android development](https://developer.android.com/topic/performance/vitals/render).
    public let slowFrames: Int


    /// Total amount of freeze durations. Freeze is an amount of time every frame rendering was delayed by in comparison with the ideal performant frame.
    /// For example if expected frame duration was 16ms, but in reality we've rendered this frame in 320ms, we have a freeze with 304ms duration.
    public let freezeTime: DispatchTimeInterval

    /// Total duration of the screen session.
    /// We count it by summing up all rendered frames duration. Not by subtracting start time from end time. So this value might be a bit inaccurate because of the rounding inconsistency.
    public let sessionDuration: DispatchTimeInterval

    /// Information about how app was started.
    ///
    /// If app was started with pre-warming or in background, it can mess rendering metrics for the first view controller to appear.
    /// You probably want to exclude such metrics.
    public let appStartInfo: AppStartInfo

    /// frozenFrames / renderedFrames.
    ///
    /// 0...1 or nil if renderedFrames is 0
    public var frozenFramesRatio: Decimal? {
        guard renderedFrames > 0 else {
            return nil
        }
        return Decimal(frozenFrames) / Decimal(renderedFrames)
    }

    /// slowFrames / renderedFrames.
    ///
    /// 0...1 or nil if renderedFrames is 0
    public var slowFramesRatio: Decimal? {
        guard renderedFrames > 0 else {
            return nil
        }
        return Decimal(slowFrames) / Decimal(renderedFrames)
    }

    /// droppedFrames / expectedFrames.
    ///
    /// 0...1 or nil if expectedFrames is 0
    public var droppedFramesRatio: Decimal? {
        guard expectedFrames > 0 else {
            return nil
        }
        return Decimal(droppedFrames) / Decimal(expectedFrames)
    }


    /// Instance with zeros in every field
    public static var zero: Self {
        return RenderingMetrics(
            renderedFrames: 0,
            expectedFrames: 0,
            droppedFrames: 0,
            frozenFrames: 0,
            slowFrames: 0,
            freezeTime: .zero,
            sessionDuration: .zero,
            appStartInfo: .empty
        )
    }

    public var description: String {
        return
            "renderedFrames: \(renderedFrames), expectedFrames: \(expectedFrames), droppedFrames: \(droppedFrames), freezeTime: \(freezeTime.milliseconds ?? 0) ms, sessionDuration: \(sessionDuration.timeInterval ?? 0) seconds"
    }

    static func metrics(frameDuration: CFTimeInterval, refreshRateDuration: CFTimeInterval) -> Self {
        let renderedFrames = 1
        let frozenFrames = frameDuration >= frozenFrameThreshold ? 1 : 0
        let slowFrames = frameDuration >= slowFrameThreshold ? 1 : 0
        let expectedFrames: Int
        let droppedFrames: Int
        if frameDuration > (refreshRateDuration + refreshRateDurationThreshold) {
            expectedFrames = Int(round(frameDuration / refreshRateDuration))
            droppedFrames = expectedFrames - 1
        } else {
            expectedFrames = 1
            droppedFrames = 0
        }

        let currentFreezeTime = frameDuration - refreshRateDuration
        let freezeTime = DispatchTimeInterval.timeInterval(currentFreezeTime)
        let sessionDuration = DispatchTimeInterval.timeInterval(frameDuration)

        return RenderingMetrics(
            renderedFrames: renderedFrames,
            expectedFrames: expectedFrames,
            droppedFrames: droppedFrames,
            frozenFrames: frozenFrames,
            slowFrames: slowFrames,
            freezeTime: freezeTime,
            sessionDuration: sessionDuration,
            appStartInfo: AppInfoHolder.appStartInfo)
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        if rhs == .zero {
            return lhs
        }
        if lhs == .zero {
            return rhs
        }
        return RenderingMetrics(
            renderedFrames: lhs.renderedFrames + rhs.renderedFrames,
            expectedFrames: lhs.expectedFrames + rhs.expectedFrames,
            droppedFrames: lhs.droppedFrames + rhs.droppedFrames,
            frozenFrames: lhs.frozenFrames + rhs.frozenFrames,
            slowFrames: lhs.slowFrames + rhs.slowFrames,
            freezeTime: lhs.freezeTime + rhs.freezeTime,
            sessionDuration: lhs.sessionDuration + rhs.sessionDuration,
            appStartInfo: AppStartInfo.merge(lhs.appStartInfo, rhs.appStartInfo)
        )
    }
}
