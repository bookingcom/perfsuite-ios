//
//  MultiWatchdogTerminationsReceiver.swift
//  PerformanceSuite
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import Foundation

/// Composite ``WatchdogTerminationsReceiver`` that fans out every event to every
/// receiver in the supplied array.
public final class MultiWatchdogTerminationsReceiver: WatchdogTerminationsReceiver {

    private let receivers: [WatchdogTerminationsReceiver]

    /// - Parameter receivers: The receivers to fan out to. Order is preserved.
    public init(receivers: [WatchdogTerminationsReceiver]) {
        self.receivers = receivers
    }

    public func watchdogTerminationReceived(_ data: WatchdogTerminationData) {
        for receiver in receivers {
            receiver.watchdogTerminationReceived(data)
        }
    }
}
