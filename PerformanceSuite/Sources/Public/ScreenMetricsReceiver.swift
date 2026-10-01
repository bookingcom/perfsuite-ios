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
/// `screenTTIMeasurementEnded` can come long after the TTI end (on `TTIMetrics.readyFallback`, at
/// `viewWillDisappear`); `TTIMetrics.reportDelay` gives the gap, so the measurement can be ended at the TTI end.
///
/// `UIViewController.screenIsBeingCreated()` opens a *pending* measurement before the screen exists
/// (`screenTTIPendingMeasurementStarted`). The next tracked screen to start measuring adopts it at its
/// `viewDidLoad`, in place of `screenTTIMeasurementStarted`; otherwise it ends with a
/// ``PendingScreenTTIEndReason``. The defaults open no pending measurement.
public protocol LiveTTIMetricsReceiver<ScreenIdentifier>: TTIMetricsReceiver {
    func screenTTIMeasurementStarted(screen: ScreenIdentifier) -> (any MeasurementHandle)?
    func screenTTIMeasurementEnded(
        metrics: TTIMetrics,
        screen: ScreenIdentifier,
        context: (any MeasurementHandle)?
    )

    /// Called from `screenIsBeingCreated()` on the caller's thread, usually the main thread, before the call returns,
    /// so work started right after the call can already see the measurement. Keep it fast. `startTime` is the
    /// call's instant.
    func screenTTIPendingMeasurementStarted(at startTime: Date) -> (any MeasurementHandle)?

    /// Called on `PerformanceMonitoring.queue` at `viewDidLoad` of the screen that adopts `pending`, in place of
    /// `screenTTIMeasurementStarted`. The returned handle is the screen's measurement; `nil` means not emitted.
    func screenTTIPendingMeasurementAdopted(
        _ pending: any MeasurementHandle,
        screen: ScreenIdentifier
    ) -> (any MeasurementHandle)?

    /// Called on `PerformanceMonitoring.queue` when no screen adopts `pending`.
    func screenTTIPendingMeasurementEnded(_ pending: any MeasurementHandle, reason: PendingScreenTTIEndReason)
}

public extension LiveTTIMetricsReceiver {
    func screenTTIPendingMeasurementStarted(at startTime: Date) -> (any MeasurementHandle)? {
        nil
    }

    func screenTTIPendingMeasurementAdopted(
        _ pending: any MeasurementHandle,
        screen: ScreenIdentifier
    ) -> (any MeasurementHandle)? {
        pending.cancel()
        return screenTTIMeasurementStarted(screen: screen)
    }

    func screenTTIPendingMeasurementEnded(_ pending: any MeasurementHandle, reason: PendingScreenTTIEndReason) {
        pending.cancel()
    }
}

/// Why a pending screen-TTI measurement ended without a screen adopting it.
public enum PendingScreenTTIEndReason: Equatable, Sendable {
    /// `UIViewController.screenCreationCancelled()` was called.
    case creationCancelled
    /// A later `screenIsBeingCreated()` call replaced it.
    case superseded
    /// A screen took the TTI start without adopting it: one that was already measuring before the call, or one
    /// that isn't measured (e.g. the app went to the background before its `viewDidLoad`).
    case notAdopted
    /// No screen adopted it in time.
    case abandoned
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
