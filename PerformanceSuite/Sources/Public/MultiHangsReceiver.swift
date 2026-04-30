//
//  MultiHangsReceiver.swift
//  PerformanceSuite
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import Foundation

/// Composite ``HangsReceiver`` that fans out every event to every receiver in the
/// supplied array.
///
/// `hangThreshold` is taken from the first receiver — it is a single value used by
/// the underlying detection timer at config time, so there is no meaningful "fan
/// out" for it. Pass the receivers in the order whose `hangThreshold` you want to
/// win, or pre-align the values across receivers if you depend on the precise
/// threshold of more than one of them.
public final class MultiHangsReceiver: HangsReceiver {

    private let receivers: [HangsReceiver]
    private let _hangThreshold: TimeInterval

    /// - Parameter receivers: The receivers to fan out to. Order is preserved. Must
    ///   contain at least one element — an empty array would leave
    ///   ``hangThreshold`` without a sensible value and would silently swallow all
    ///   hang events.
    public init(receivers: [HangsReceiver]) {
        precondition(!receivers.isEmpty, "MultiHangsReceiver requires at least one receiver")
        self.receivers = receivers
        self._hangThreshold = receivers[0].hangThreshold
    }

    public var hangThreshold: TimeInterval {
        _hangThreshold
    }

    public func fatalHangReceived(info: HangInfo) {
        for receiver in receivers {
            receiver.fatalHangReceived(info: info)
        }
    }

    public func nonFatalHangReceived(info: HangInfo) {
        for receiver in receivers {
            receiver.nonFatalHangReceived(info: info)
        }
    }

    public func hangStarted(info: HangInfo) {
        for receiver in receivers {
            receiver.hangStarted(info: info)
        }
    }
}
