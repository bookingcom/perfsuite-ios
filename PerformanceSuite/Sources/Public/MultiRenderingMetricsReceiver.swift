//
//  MultiRenderingMetricsReceiver.swift
//  PerformanceSuite
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import UIKit

/// Composite ``RenderingMetricsReceiver`` that fans out every event to every receiver
/// in the supplied array. See ``MultiTTIMetricsReceiver`` for design notes that apply
/// equally here.
///
/// - Note: Requires iOS 16 or later. See ``MultiTTIMetricsReceiver`` for the rationale.
@available(iOS 16.0, *)
public final class MultiRenderingMetricsReceiver<Screen>: RenderingMetricsReceiver {

    public typealias ScreenIdentifier = Screen

    private let _screenIdentifier: (UIViewController) -> Screen?
    private let receivers: [any RenderingMetricsReceiver<Screen>]

    /// - Parameters:
    ///   - screenIdentifier: Closure that maps `UIViewController` instances to ``Screen``.
    ///     See ``MultiTTIMetricsReceiver/init(screenIdentifier:receivers:)`` for the contract.
    ///   - receivers: The receivers to fan out to. Order is preserved.
    public init(
        screenIdentifier: @escaping (UIViewController) -> Screen?,
        receivers: [any RenderingMetricsReceiver<Screen>]
    ) {
        self._screenIdentifier = screenIdentifier
        self.receivers = receivers
    }

    public func screenIdentifier(for viewController: UIViewController) -> Screen? {
        _screenIdentifier(viewController)
    }

    public func renderingMetricsReceived(metrics: RenderingMetrics, screen: Screen) {
        for receiver in receivers {
            receiver.renderingMetricsReceived(metrics: metrics, screen: screen)
        }
    }
}
