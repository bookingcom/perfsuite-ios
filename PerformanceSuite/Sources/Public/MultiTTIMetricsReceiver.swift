//
//  MultiTTIMetricsReceiver.swift
//  PerformanceSuite
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import UIKit

/// Composite ``TTIMetricsReceiver`` that fans out every event to every receiver in the
/// supplied array. Useful when the same TTI signal must reach multiple consumers
/// (e.g. an analytics receiver and a separate OpenTelemetry receiver) without having
/// to duplicate the dispatch logic in each reporter.
///
/// `screenIdentifier(for:)` is provided as a separate closure rather than delegated
/// to one of the wrapped receivers — this avoids ambiguity about whose mapping wins
/// when the receivers disagree, and lets callers reuse a single screen-identifier
/// implementation across multiple ``Multi``*Receiver instances.
///
/// - Note: Requires iOS 16 or later because the heterogeneous receiver array uses
///   constrained existential types (`any TTIMetricsReceiver<Screen>`), whose runtime
///   support shipped with iOS 16. iOS 15 consumers of `PerformanceSuite` that need
///   to combine receivers must implement their own composition.
@available(iOS 16.0, *)
public final class MultiTTIMetricsReceiver<Screen>: TTIMetricsReceiver {

    public typealias ScreenIdentifier = Screen

    private let _screenIdentifier: (UIViewController) -> Screen?
    private let receivers: [any TTIMetricsReceiver<Screen>]

    /// - Parameters:
    ///   - screenIdentifier: Closure that maps `UIViewController` instances to ``Screen``.
    ///     Mirrors the contract of ``ScreenMetricsReceiver/screenIdentifier(for:)``: return
    ///     `nil` for view controllers that should not be tracked. Must be fast — it is
    ///     invoked on the internal performance queue during `init` of every observed
    ///     view controller.
    ///   - receivers: The receivers to fan out to. Order is preserved; each receiver
    ///     is invoked synchronously on the consumer queue in the order supplied.
    public init(
        screenIdentifier: @escaping (UIViewController) -> Screen?,
        receivers: [any TTIMetricsReceiver<Screen>]
    ) {
        self._screenIdentifier = screenIdentifier
        self.receivers = receivers
    }

    public func screenIdentifier(for viewController: UIViewController) -> Screen? {
        _screenIdentifier(viewController)
    }

    public func ttiMetricsReceived(metrics: TTIMetrics, screen: Screen) {
        for receiver in receivers {
            receiver.ttiMetricsReceived(metrics: metrics, screen: screen)
        }
    }
}
