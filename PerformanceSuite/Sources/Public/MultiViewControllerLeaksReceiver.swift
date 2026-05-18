//
//  MultiViewControllerLeaksReceiver.swift
//  PerformanceSuite
//
//  Created by Ahmed Nafei on 18/05/2026.
//

import UIKit

/// Composite ``ViewControllerLeaksReceiver`` that fans out every leak event to
/// every child receiver in the supplied array.
///
/// An optional `shouldTrack` closure provides a single chain-wide opt-out: if
/// the closure returns `false` for a given view controller, the event is not
/// forwarded to any child and ``shouldTrack(viewController:)`` returns `false`
/// (so ``ViewControllerLeaksObserver`` skips the dispatch entirely instead of
/// queuing a no-op). When `shouldTrack` is `nil`, every leak reaches every
/// child.
///
/// The Multi does *not* consult each child's
/// ``ViewControllerLeaksReceiver/shouldTrack(viewController:)`` because there is
/// no real use case today for asymmetric per-child gating. A custom receiver
/// that wants per-VC opt-out can implement the filter inside
/// ``viewControllerLeakReceived(viewController:)`` itself, the same way iosapp's
/// `ViewControllerLeaksReceiverImpl` already does for its squeak path.
///
/// An empty `receivers` array is a valid no-op chain.
public final class MultiViewControllerLeaksReceiver: ViewControllerLeaksReceiver {

    private let receivers: [ViewControllerLeaksReceiver]
    private let _shouldTrack: ((UIViewController) -> Bool)?

    /// - Parameters:
    ///   - receivers: The receivers to fan out to. Order is preserved.
    ///   - shouldTrack: Optional chain-wide predicate. When non-nil and returning
    ///     `false`, the leak is suppressed for every child and the observer is
    ///     told to skip dispatch via ``shouldTrack(viewController:)``.
    public init(
        receivers: [ViewControllerLeaksReceiver],
        shouldTrack: ((UIViewController) -> Bool)? = nil
    ) {
        self.receivers = receivers
        self._shouldTrack = shouldTrack
    }

    public func viewControllerLeakReceived(viewController: UIViewController) {
        guard _shouldTrack?(viewController) ?? true else { return }
        for receiver in receivers {
            receiver.viewControllerLeakReceived(viewController: viewController)
        }
    }

    public func shouldTrack(viewController: UIViewController) -> Bool {
        _shouldTrack?(viewController) ?? true
    }
}
