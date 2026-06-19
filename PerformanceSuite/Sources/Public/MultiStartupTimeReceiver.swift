//
//  MultiStartupTimeReceiver.swift
//  PerformanceSuite
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import Foundation

/// Composite ``StartupTimeReceiver`` that fans out every event to every receiver
/// in the supplied array. At most one receiver may be live.
public final class MultiStartupTimeReceiver: LiveStartupTimeReceiver {

    private let receivers: [StartupTimeReceiver]
    private let liveReceiver: LiveStartupTimeReceiver?

    /// - Parameter receivers: The receivers to fan out to. Order is preserved.
    public init(receivers: [StartupTimeReceiver]) {
        self.receivers = receivers
        let live = receivers.compactMap { $0 as? LiveStartupTimeReceiver }
        assert(live.count <= 1, "MultiStartupTimeReceiver supports at most one live receiver")
        self.liveReceiver = live.first
    }

    public func startupTimeReceived(_ data: StartupTimeData) {
        for receiver in receivers {
            receiver.startupTimeReceived(data)
        }
    }

    public func startupMeasurementStarted() -> (any MeasurementHandle)? {
        liveReceiver?.startupMeasurementStarted()
    }

    public func startupMeasurementEnded(
        _ data: StartupTimeData,
        context: (any MeasurementHandle)?
    ) {
        liveReceiver?.startupMeasurementEnded(data, context: context)
        for receiver in receivers where receiver !== liveReceiver {
            receiver.startupTimeReceived(data)
        }
    }
}
