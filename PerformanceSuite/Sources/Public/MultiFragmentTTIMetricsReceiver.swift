//
//  MultiFragmentTTIMetricsReceiver.swift
//  PerformanceSuite
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import Foundation

/// Composite ``FragmentTTIMetricsReceiver`` that fans out every event to every
/// receiver in the supplied array. Unlike ``MultiTTIMetricsReceiver`` there is no
/// view-controller-to-identifier mapping closure here — the fragment identifier is
/// provided by the caller of ``PerformanceMonitoring/startFragmentTTI(identifier:)``,
/// so this composite simply forwards what it receives.
///
/// - Note: Requires iOS 16 or later. See ``MultiTTIMetricsReceiver`` for the rationale.
@available(iOS 16.0, *)
public final class MultiFragmentTTIMetricsReceiver<Fragment>: FragmentTTIMetricsReceiver {

    public typealias FragmentIdentifier = Fragment

    private let receivers: [any FragmentTTIMetricsReceiver<Fragment>]

    /// - Parameter receivers: The receivers to fan out to. Order is preserved.
    public init(receivers: [any FragmentTTIMetricsReceiver<Fragment>]) {
        self.receivers = receivers
    }

    public func fragmentTTIMetricsReceived(metrics: TTIMetrics, fragment: Fragment) {
        for receiver in receivers {
            receiver.fragmentTTIMetricsReceived(metrics: metrics, fragment: fragment)
        }
    }
}
