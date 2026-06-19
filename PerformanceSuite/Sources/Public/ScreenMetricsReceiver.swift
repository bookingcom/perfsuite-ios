//
//  MetricsConsumer.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 07/07/2021.
//

import UIKit

// MARK: - Live measurement dispatch
// Live measurements are opt-in: a receiver conforms to a `Live*MetricsReceiver` sub-protocol and the reporter
// starts/ends a measurement via an iOS-16 constrained-existential cast. Plain receivers conform only to the
// base protocol and keep getting the completed `*Received` callback.

/// Base protocol for screen-level TTI and Rendering receivers
public protocol ScreenMetricsReceiver<ScreenIdentifier>: AnyObject {
    /// ScreenIdentifier can be String, some enum, or UIViewController itself.
    associatedtype ScreenIdentifier

    /// Converts a `UIViewController` to `ScreenIdentifier`. Return `nil` to skip tracking.
    /// Called once on the main thread during `UIViewController` initialization; keep it fast.
    /// Default returns nil for non-main-bundle view controllers and the controller itself otherwise.
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
public protocol TTIMetricsReceiver<ScreenIdentifier>: ScreenMetricsReceiver {
    /// Called when TTI metrics are calculated for some screen on `consumerQueue` after
    /// `viewDidAppear`. `Config.screenLevelTTI` must be enabled.
    func ttiMetricsReceived(metrics: TTIMetrics, screen: ScreenIdentifier)
}

/// Opt-in live-measurement variant of ``TTIMetricsReceiver`` — measurement started when the screen is created, ended
/// when TTI resolves; `cancel()` covers abandonment. Requires iOS 16. No start `Date` is passed (unlike
/// rendering), so the measurement's wall-clock duration may differ slightly from the `TTIMetrics.tti` attribute.
public protocol LiveTTIMetricsReceiver<ScreenIdentifier>: TTIMetricsReceiver {
    func screenTTIMeasurementStarted(screen: ScreenIdentifier) -> (any MeasurementHandle)?
    func screenTTIMeasurementEnded(
        metrics: TTIMetrics,
        screen: ScreenIdentifier,
        context: (any MeasurementHandle)?
    )
}


/// You should implement this protocol to receive screen-level rendering metrics in your code.
///
/// Pass instance of this protocol to the config item `ConfigItem.screenLevelRendering`
public protocol RenderingMetricsReceiver<ScreenIdentifier>: ScreenMetricsReceiver {
    /// Called when rendering metrics are calculated for some screen on `consumerQueue`
    /// after `viewWillDisappear`. `Config.screenLevelRendering` must be enabled.
    func renderingMetricsReceived(metrics: RenderingMetrics, screen: ScreenIdentifier)
}

/// Opt-in live-measurement variant of ``RenderingMetricsReceiver``. `sessionStarted` is the wall-clock `Date`
/// captured synchronously at `viewDidAppear` before the queue hop, for a precise measurement start time.
/// Requires iOS 16.
public protocol LiveRenderingMetricsReceiver<ScreenIdentifier>: RenderingMetricsReceiver {
    func screenRenderingStarted(
        screen: ScreenIdentifier,
        sessionStarted: Date
    ) -> (any MeasurementHandle)?
    func screenRenderingEnded(
        metrics: RenderingMetrics,
        screen: ScreenIdentifier,
        context: (any MeasurementHandle)?
    )
}
