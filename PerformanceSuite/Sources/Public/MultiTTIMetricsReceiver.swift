//
//  MultiTTIMetricsReceiver.swift
//  PerformanceSuite
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import UIKit

/// Composite ``TTIMetricsReceiver`` that fans out every event to every receiver in the
/// supplied array. Useful when the same TTI signal must reach multiple consumers
/// (e.g. an analytics receiver and a separate live/telemetry receiver).
///
/// `screenIdentifier(for:)` is provided as a separate closure rather than delegated
/// to one of the wrapped receivers, so callers reuse a single mapping across instances.
///
/// At most one wrapped receiver may be live (conform to ``LiveTTIMetricsReceiver``); a
/// live child drives the measurement and is finalised first, then the others get the completed
/// ``TTIMetricsReceiver`` callback in array order.
///
/// - Note: Requires iOS 16+ — the heterogeneous array uses constrained existential types.
@available(iOS 16.0, *)
public final class MultiTTIMetricsReceiver<Screen>: LiveTTIMetricsReceiver {

    public typealias ScreenIdentifier = Screen

    private let _screenIdentifier: (UIViewController) -> Screen?
    private let receivers: [any TTIMetricsReceiver<Screen>]
    private let liveReceiver: (any LiveTTIMetricsReceiver<Screen>)?

    public init(
        screenIdentifier: @escaping (UIViewController) -> Screen?,
        receivers: [any TTIMetricsReceiver<Screen>]
    ) {
        self._screenIdentifier = screenIdentifier
        self.receivers = receivers
        let live = receivers.compactMap { $0 as? any LiveTTIMetricsReceiver<Screen> }
        assert(live.count <= 1, "MultiTTIMetricsReceiver supports at most one live receiver")
        self.liveReceiver = live.first
    }

    public func screenIdentifier(for viewController: UIViewController) -> Screen? {
        _screenIdentifier(viewController)
    }

    public func ttiMetricsReceived(metrics: TTIMetrics, screen: Screen) {
        for receiver in receivers {
            receiver.ttiMetricsReceived(metrics: metrics, screen: screen)
        }
    }

    public func screenTTIMeasurementStarted(screen: Screen) -> (any MeasurementHandle)? {
        liveReceiver?.screenTTIMeasurementStarted(screen: screen)
    }

    public func screenTTIMeasurementEnded(
        metrics: TTIMetrics,
        screen: Screen,
        context: (any MeasurementHandle)?
    ) {
        liveReceiver?.screenTTIMeasurementEnded(metrics: metrics, screen: screen, context: context)
        for receiver in receivers where receiver !== liveReceiver {
            receiver.ttiMetricsReceived(metrics: metrics, screen: screen)
        }
    }
}
