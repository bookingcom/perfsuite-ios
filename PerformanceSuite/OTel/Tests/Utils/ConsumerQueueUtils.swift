//
//  ConsumerQueueUtils.swift
//  PerformanceSuite
//

import Foundation

@testable import PerformanceSuite

/// Raises the priority of the blocks queued on `consumerQueue`, including those that work on `PerformanceMonitoring.queue`
/// queues, for tests that wait for them without draining the queue from the waiting thread.
///
/// `consumerQueue` has background QoS, and on a busy CI runner its blocks can wait for many seconds. A `sync` from a
/// user-initiated thread raises the queue's priority until it reaches the blocks queued before it.
/// Lives with the OTel tests so that their Swift package test target compiles it too.
func prioritizeConsumerQueue() {
    PerformanceMonitoring.queue.sync {}
    DispatchQueue.global(qos: .userInitiated).async {
        PerformanceMonitoring.consumerQueue.sync {}
    }
}
