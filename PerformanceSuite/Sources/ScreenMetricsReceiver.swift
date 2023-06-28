//
//  MetricsConsumer.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 07/07/2021.
//

import UIKit

/// Base protocol for screen-level TTI and Rendering receivers
public protocol ScreenMetricsReceiver: AnyObject {
    /// We can disable tracking for some of the view controllers.
    ///
    /// Default implementation will ignore view controllers that are not from the main bundle.
    ///
    /// For example Apple's UINavigationController, UITabbarController, UIHostingController and so on.
    ///
    /// - Parameter viewController: should we enable tracking for this controller?
    func shouldTrack(viewController: UIViewController) -> Bool
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
    ///   - viewController: view controller instance for which we calculated those TTI metrics
    func ttiMetricsReceived(metrics: TTIMetrics, viewController: UIViewController)
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
    ///   - viewController: view controller instance for which we calculated those rendering metrics
    func renderingMetricsReceived(metrics: RenderingMetrics, viewController: UIViewController)
}


public extension ScreenMetricsReceiver {
    /// The default implementation will track only view controllers from the main bundle
    func shouldTrack(viewController: UIViewController) -> Bool {
        return Bundle(for: type(of: viewController)) == Bundle.main
    }
}
