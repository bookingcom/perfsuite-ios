//
//  MultiAppRenderingMetricsReceiver.swift
//  PerformanceSuite
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import Foundation

/// Composite ``AppRenderingMetricsReceiver`` that fans out every event to every receiver. At most
/// one receiver may be live; the session start/end signals are delivered only to that live child.
public final class MultiAppRenderingMetricsReceiver: LiveAppRenderingMetricsReceiver {

    private let receivers: [AppRenderingMetricsReceiver]
    private let liveReceiver: LiveAppRenderingMetricsReceiver?

    /// - Parameter receivers: The receivers to fan out to. Order is preserved.
    public init(receivers: [AppRenderingMetricsReceiver]) {
        self.receivers = receivers
        let live = receivers.compactMap { $0 as? LiveAppRenderingMetricsReceiver }
        assert(live.count <= 1, "MultiAppRenderingMetricsReceiver supports at most one live receiver")
        self.liveReceiver = live.first
    }

    public func appRenderingMetricsReceived(metrics: RenderingMetrics) {
        for receiver in receivers {
            receiver.appRenderingMetricsReceived(metrics: metrics)
        }
    }

    public func appRenderingSessionStarted(at startedAt: Date) {
        liveReceiver?.appRenderingSessionStarted(at: startedAt)
    }

    public func appRenderingSessionEnded() {
        liveReceiver?.appRenderingSessionEnded()
    }
}
