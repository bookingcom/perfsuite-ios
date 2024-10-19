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

    public var description: String {
        return "tti: \(tti.milliseconds ?? 0) ms, ttfr: \(ttfr.milliseconds ?? 0) ms"
    }
}
