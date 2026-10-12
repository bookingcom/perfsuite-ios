//
//  MultiFragmentRenderingMetricsReceiver.swift
//  PerformanceSuite
//
//  Created by Luis Resende on 12/10/2026.
//

import Foundation

/// Composite ``FragmentRenderingMetricsReceiver`` that fans out every event to every
/// receiver in the supplied array. At most one receiver may be live.
///
/// - Note: Requires iOS 16 or later. See ``MultiFragmentTTIMetricsReceiver`` for the rationale.
@available(iOS 16.0, *)
public final class MultiFragmentRenderingMetricsReceiver<Fragment>: LiveFragmentRenderingMetricsReceiver {

    public typealias FragmentIdentifier = Fragment

    private let receivers: [any FragmentRenderingMetricsReceiver<Fragment>]
    private let liveReceiver: (any LiveFragmentRenderingMetricsReceiver<Fragment>)?

    public init(receivers: [any FragmentRenderingMetricsReceiver<Fragment>]) {
        self.receivers = receivers
        let live = receivers.compactMap { $0 as? any LiveFragmentRenderingMetricsReceiver<Fragment> }
        assert(live.count <= 1, "MultiFragmentRenderingMetricsReceiver supports at most one live receiver")
        self.liveReceiver = live.first
    }

    public func fragmentRenderingMetricsReceived(metrics: RenderingMetrics, fragment: Fragment) {
        for receiver in receivers {
            receiver.fragmentRenderingMetricsReceived(metrics: metrics, fragment: fragment)
        }
    }

    public func fragmentRenderingStarted(fragment: Fragment) -> (any MeasurementHandle)? {
        liveReceiver?.fragmentRenderingStarted(fragment: fragment)
    }

    public func fragmentRenderingEnded(
        metrics: RenderingMetrics,
        fragment: Fragment,
        context: (any MeasurementHandle)?
    ) {
        liveReceiver?.fragmentRenderingEnded(metrics: metrics, fragment: fragment, context: context)
        for receiver in receivers where receiver !== liveReceiver {
            receiver.fragmentRenderingMetricsReceived(metrics: metrics, fragment: fragment)
        }
    }
}
