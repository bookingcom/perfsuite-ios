//
//  TTIMetrics.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 26/01/2022.
//

import Foundation

/// All the data that we gather about screen TTI
public struct TTIMetrics: CustomStringConvertible, Equatable {

    /// Time to interactive
    ///
    /// Time between view controller is created and view controller displays all data:
    /// ViewController.init -> ViewController.screenIsReady
    public let tti: DispatchTimeInterval

    /// Time to first frame
    ///
    /// Time between view controller is created and view controller displays it's first frame.
    /// ViewController.init -> ViewController.viewDidAppear
    public let ttfr: DispatchTimeInterval

    /// If app was started with pre-warming or in background, it can mess TTI for the first view controller to appear.
    /// You probably want to exclude such TTI measurements.
    public let appStartInfo: AppStartInfo

    /// `true` when `screenIsReady()` was never called and TTI fell back to `viewDidAppear` at `viewWillDisappear`.
    public var readyFallback: Bool = false

    /// Time from the TTI end, `max(screenIsReady, viewDidAppear)`, to the moment these metrics were reported.
    /// Large mostly on the `readyFallback` path, where the report waits for `viewWillDisappear`.
    public var reportDelay: DispatchTimeInterval = .zero

    /// `true` when TTI started at a `UIViewController.screenIsBeingCreated()` call instead of the screen's own creation.
    public var customStart: Bool = false

    public var description: String {
        let base = "tti: \(tti.milliseconds ?? 0) ms, ttfr: \(ttfr.milliseconds ?? 0) ms"
        return readyFallback ? base + ", ready_fallback: true" : base
    }
}
