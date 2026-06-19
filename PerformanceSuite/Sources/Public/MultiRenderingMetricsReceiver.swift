//
//  MultiRenderingMetricsReceiver.swift
//  PerformanceSuite
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import UIKit

/// Composite ``RenderingMetricsReceiver`` that fans out every event to every receiver
/// in the supplied array. See ``MultiTTIMetricsReceiver`` for design notes that apply
/// equally here, including the at-most-one-live-receiver rule.
///
/// - Note: Requires iOS 16 or later. See ``MultiTTIMetricsReceiver`` for the rationale.
@available(iOS 16.0, *)
public final class MultiRenderingMetricsReceiver<Screen>: LiveRenderingMetricsReceiver {

    public typealias ScreenIdentifier = Screen

    private let _screenIdentifier: (UIViewController) -> Screen?
    private let receivers: [any RenderingMetricsReceiver<Screen>]
    private let liveReceiver: (any LiveRenderingMetricsReceiver<Screen>)?

    public init(
        screenIdentifier: @escaping (UIViewController) -> Screen?,
        receivers: [any RenderingMetricsReceiver<Screen>]
    ) {
        self._screenIdentifier = screenIdentifier
        self.receivers = receivers
        let live = receivers.compactMap { $0 as? any LiveRenderingMetricsReceiver<Screen> }
        assert(live.count <= 1, "MultiRenderingMetricsReceiver supports at most one live receiver")
        self.liveReceiver = live.first
    }

    public func screenIdentifier(for viewController: UIViewController) -> Screen? {
        _screenIdentifier(viewController)
    }

    public func renderingMetricsReceived(metrics: RenderingMetrics, screen: Screen) {
        for receiver in receivers {
            receiver.renderingMetricsReceived(metrics: metrics, screen: screen)
        }
    }

    public func screenRenderingStarted(
        screen: Screen,
        sessionStarted: Date
    ) -> (any MeasurementHandle)? {
        liveReceiver?.screenRenderingStarted(screen: screen, sessionStarted: sessionStarted)
    }

    public func screenRenderingEnded(
        metrics: RenderingMetrics,
        screen: Screen,
        context: (any MeasurementHandle)?
    ) {
        // The live child finalises first (an empty session is signal for it). The legacy children
        // only get the completed callback when the session has signal — standalone they'd drop an
        // empty one — so they're gated and never see an empty-session leak.
        liveReceiver?.screenRenderingEnded(metrics: metrics, screen: screen, context: context)
        guard !metrics.hasNoRenderingSignal else { return }
        for receiver in receivers where receiver !== liveReceiver {
            receiver.renderingMetricsReceived(metrics: metrics, screen: screen)
        }
    }
}
