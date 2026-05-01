//
//  MultiStartupTimeReceiver.swift
//  PerformanceSuite
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import Foundation

/// Composite ``StartupTimeReceiver`` that fans out every event to every receiver
/// in the supplied array.
public final class MultiStartupTimeReceiver: StartupTimeReceiver {

    private let receivers: [StartupTimeReceiver]

    /// - Parameter receivers: The receivers to fan out to. Order is preserved.
    public init(receivers: [StartupTimeReceiver]) {
        self.receivers = receivers
    }

    public func startupTimeReceived(_ data: StartupTimeData) {
        for receiver in receivers {
            receiver.startupTimeReceived(data)
        }
    }
}
