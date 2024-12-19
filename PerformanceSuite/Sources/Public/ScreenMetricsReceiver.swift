//
//  MetricsConsumer.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 07/07/2021.
//

import UIKit

/// Base protocol for screen-level TTI and Rendering receivers
public protocol ScreenMetricsReceiver: AnyObject {
    /// ScreenIdentifier can be String, some enum, or UIViewController itself.
    associatedtype ScreenIdentifier

    /// Method converts `UIViewController` instance to `ScreenIdentifier`. It can be enum or String, which identifies your screen.
    /// Return `nil` if we shouldn't track metrics for this `UIViewController`.
    /// This method should be as effective as possible. Slow implementation may harm app performance.
    ///
    /// This method is called on the main thread only once, during `UIViewController` initialization.
    /// This method is called on the background internal queue `PerformanceMonitoring.queue`.
    /// Slow implementation may harm overall performance and also can affect the precision of the measurements.
    ///
    /// Default implementation will return nil for view controllers that are not from the main bundle and return `UIViewController` itself for others
    ///
    /// - Parameter viewController: `UIViewController` which is being tracked
    func screenIdentifier(for viewController: UIViewController) -> ScreenIdentifier?
}

public extension ScreenMetricsReceiver where ScreenIdentifier == UIViewController {

    /// Default implementation that just returns the viewController itself
    func screenIdentifier(for viewController: UIViewController) -> UIViewController? {
        /// We track only view controllers from the main bundle by default
        guard Bundle(for: type(of: viewController)) == Bundle.main else {
            return nil
        }
        return viewController
    }
}


/// You should implement this protocol to receive TTI metrics in your code.
///
/// Pass instance of this protocol to the config item `ConfigItem.screenLevelTTI`
public protocol TTIMetricsReceiver: ScreenMetricsReceiver {
    /// Method is called when TTI metrics are calculated for some screen.
    ///
    /// `Config.screenLevelTTI` should be enabled.
    ///
    /// Method is called on a separate background queue `PerformanceMonitoring.consumerQueue`.
    ///
    /// It is called after screen is ready and view controller `viewDidAppear` method is called.
    ///
    /// - Parameters:
    ///   - metrics: calculated TTI metrics
    ///   - screen: screen for which we calculated those TTI metrics
    func ttiMetricsReceived(metrics: TTIMetrics, screen: ScreenIdentifier)
}


/// You should implement this protocol to receive screen-level rendering metrics in your code.
///
/// Pass instance of this protocol to the config item `ConfigItem.screenLevelRendering`
public protocol RenderingMetricsReceiver: ScreenMetricsReceiver {
    /// Method is called when performance metrics are calculated for some screen.
    ///
    /// `Config.screenLevelRendering` should be enabled.
    ///
    /// Method is called on a separate background queue `PerformanceMonitoring.consumerQueue`.
    ///
    /// It is called after screen disappeared, when `viewWillDisappear` method is called.
    ///
    /// - Parameters:
    ///   - metrics: calculated rendering metrics
    ///   - screen: screen for which we calculated those rendering metrics
    func renderingMetricsReceived(metrics: RenderingMetrics, screen: ScreenIdentifier)
}
