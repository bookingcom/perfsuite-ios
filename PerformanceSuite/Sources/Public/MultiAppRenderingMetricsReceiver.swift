//
//  MultiAppRenderingMetricsReceiver.swift
//  PerformanceSuite
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import Foundation

/// Composite ``AppRenderingMetricsReceiver`` that fans out every event to every
/// receiver in the supplied array.
public final class MultiAppRenderingMetricsReceiver: AppRenderingMetricsReceiver {

    private let receivers: [AppRenderingMetricsReceiver]

    /// - Parameter receivers: The receivers to fan out to. Order is preserved.
    public init(receivers: [AppRenderingMetricsReceiver]) {
        self.receivers = receivers
    }

    public func appRenderingMetricsReceived(metrics: RenderingMetrics) {
        for receiver in receivers {
            receiver.appRenderingMetricsReceived(metrics: metrics)
        }
    }
}
