//
//  PerformanceMonitoring+Extensions.swift
//  PerformanceSuite
//
//  Created by Luis Resende on 15/10/2026.
//

import Foundation

// MARK: - Fragment Rendering

extension PerformanceMonitoring {
    static func makeFragmentRenderingReporter<F: FragmentRenderingMetricsReceiver>(
        metricsReceiver: F, framesMeter: FramesMeter
    ) -> AppMetricsReporter {
        AnyFragmentRenderingReporter(
            reporter: FragmentRenderingReporter(metricsReceiver: metricsReceiver, framesMeter: framesMeter))
    }

    static func appendFragmentRenderingReporter(
        config: Config, framesMeter: FramesMeter, appReporters: inout [AppMetricsReporter]
    ) {
        guard let fragmentRenderingReceiver = config.fragmentRenderingReceiver else {
            return
        }
        let reporter = makeFragmentRenderingReporter(metricsReceiver: fragmentRenderingReceiver, framesMeter: framesMeter)
        appReporters.append(reporter)
    }
}

// MARK: - Queues

extension PerformanceMonitoring {

    /// This method might be used in tests to replace `PerformanceMonitoring.queue` with the main queue and after the test revert it back.
    /// It might be useful in tests, where you test methods which should be called from `PerformanceMonitoring.queue`.
    /// - Parameter newQueue: new queue to set as `PerformanceMonitoring.queue`
    /// - Returns:old queue, which was replaced
    @discardableResult
    static func changeQueueForTests(_ newQueue: DispatchQueue) -> DispatchQueue {
        let oldQueue = queue
        // Clear the key from the queue being swapped out so it isn't left permanently identified as
        // PM.queue (e.g. a test swapping in `.main` must not leave `.main` keyed after it restores,
        // which would make later `runOnQueue` calls on main run inline instead of dispatching).
        oldQueue.setSpecific(key: queueKey, value: nil)
        queue = newQueue
        // Re-stamp queueKey so runOnQueue detects the swapped-in queue (see runOnQueue).
        newQueue.setSpecific(key: queueKey, value: ())
        return oldQueue
    }

    /// This queue is used for all the monitoring logic. It is interactive because we should react faster for proper measurements
    /// It is `var`, not `let` only to be able to replace it in tests. Do not change it in production.
    static private(set) var queue: DispatchQueue = {
        let q = DispatchQueue(label: "performance_suite_monitoring_queue", qos: .userInteractive)
        q.setSpecific(key: queueKey, value: ())
        return q
    }()

    /// This queue is used to send data to the consumer. It is background because we don't need to be fast there
    static let consumerQueue = DispatchQueue(label: "performance_suite_consumer_queue", qos: .background)

    /// Identifies PM.queue so runOnQueue runs inline instead of deadlocking on queue.sync.
    static let queueKey = DispatchSpecificKey<Void>()

    // Run `work` on `PerformanceMonitoring.queue` synchronously. Inline when already on PM.queue
    // (detected via queueKey); avoids the queue.sync self-deadlock when tests swap queue to .main.
    static func runOnQueue(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            work()
        } else {
            queue.sync(execute: work)
        }
    }
}
