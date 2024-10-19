//
//  FragmentTTIReporter.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 21/12/2022.
//

import Foundation

/// Object which is returned from `FragmentTTIReporter.startTTI` method.
/// You can use it to stop fragment TTI
public protocol FragmentTTITrackable: AnyObject {

    /// Call this method when initial rendering of your fragment is finished.
    /// It is optional, if you not call it, TTFR will be equal to TTI.
    func fragmentIsRendered()


    /// Call this method when your fragment becomes interactive and meaningful content is displayed.
    /// If you do not call this method, no TTI will be reported for the corresponding `startTTI`call.
    func fragmentIsReady()
}


/// Implement this protocol if you want to receive events about Fragment TTI
public protocol FragmentTTIMetricsReceiver: AnyObject {
    /// This can be String, or enum or any other identifier
    associatedtype FragmentIdentifier


    /// Method is called when TTI metrics are calculated for some fragment.
    ///
    /// `Config.fragmentTTI` should be enabled.
    ///
    /// Method is called on a separate background queue `PerformanceMonitoring.consumerQueue`.
    ///
    /// It is called after `fragmentIsReady` is executed on `FragmentTTITrackable` object,
    /// which is returned from `PerformanceMonitoring.startFragmentTTI`.
    ///
    /// - Parameters:
    ///   - metrics: TTI metric for the fragment
    ///   - fragment: fragment identifier for which we received the metrics
    func fragmentTTIMetricsReceived(metrics: TTIMetrics, fragment: FragmentIdentifier)
}

private class Trackable<F: FragmentTTIMetricsReceiver>: FragmentTTITrackable {

    private let identifier: F.FragmentIdentifier
    private let timeProvider: TimeProvider
    private let metricsReceiver: F
    private let appStateListener: AppStateListener
    private weak var reporter: FragmentTTIReporter<F>?

    private let createdTime: DispatchTime
    private var isRenderedTime: DispatchTime?
    private var ttiCalculated = false


    init(
        identifier: F.FragmentIdentifier,
        timeProvider: TimeProvider,
        metricsReceiver: F,
        appStateListener: AppStateListener,
        reporter: FragmentTTIReporter<F>
    ) {
        self.identifier = identifier
        self.timeProvider = timeProvider
        self.metricsReceiver = metricsReceiver
        self.appStateListener = appStateListener
        self.reporter = reporter
        self.createdTime = timeProvider.now()
    }

    func fragmentIsRendered() {
        let now = timeProvider.now()
        PerformanceMonitoring.queue.async {
            self.isRenderedTime = now
        }
    }

    func fragmentIsReady() {
        let now = timeProvider.now()
        PerformanceMonitoring.queue.async {
            self.reportTTI(now: now)
        }
    }

    private func reportTTI(now: DispatchTime) {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        if ttiCalculated {
            // consecutive calls of `fragmentIsReady` shouldn't send anything
            return
        }

        if appStateListener.wasInBackground {
            // we ignore events when app went into background during screen session, because TTI will be too long
            return
        }


        let ttiStartTime = createdTime
        let ttiEndTime = now
        let tti = ttiStartTime.distance(to: ttiEndTime)
        if tti < .zero {
            assertionFailure("We received negative TTI  for \(identifier) that should never happen")
            return
        }

        let ttfrStartTime = createdTime
        // if `fragmentIsRendred` wasn't called, we take time of `fragmentIsReady` for TTFR end
        let ttfrEndTime = isRenderedTime ?? now
        let ttfr = ttfrStartTime.distance(to: ttfrEndTime)
        if ttfr < .zero {
            assertionFailure("We received negative TTFR  for \(identifier) that should never happen")
            return
        }

        let metrics = TTIMetrics(tti: tti, ttfr: ttfr, appStartInfo: AppInfoHolder.appStartInfo)
        PerformanceMonitoring.consumerQueue.async {
            self.metricsReceiver.fragmentTTIMetricsReceived(metrics: metrics, fragment: self.identifier)
        }

        ttiCalculated = true
    }
}

class FragmentTTIReporter<F: FragmentTTIMetricsReceiver>: AppMetricsReporter {

    init(
        metricsReceiver: F, timeProvider: TimeProvider = defaultTimeProvider,
        appStateListenerFactory: @escaping () -> AppStateListener = { DefaultAppStateListener() }
    ) {
        self.metricsReceiver = metricsReceiver
        self.timeProvider = timeProvider
        self.appStateListenerFactory = appStateListenerFactory
    }

    private let metricsReceiver: F
    private let timeProvider: TimeProvider
    private let appStateListenerFactory: () -> AppStateListener

    func start(identifier: F.FragmentIdentifier) -> FragmentTTITrackable {
        let fragment: Trackable<F> = Trackable(
            identifier: identifier,
            timeProvider: timeProvider,
            metricsReceiver: metricsReceiver,
            appStateListener: appStateListenerFactory(),
            reporter: self)
        return fragment
    }
}

/// Stub trackable object which is returned in case no FragmentTTIReporter is registered
class EmptyFragmentTTITrackable: FragmentTTITrackable {
    func fragmentIsReady() {
        preconditionFailure("You've called startFragmentTTI without registering FragmentTTIReceiver properly")
    }
    func fragmentIsRendered() {
        preconditionFailure("You've called startFragmentTTI without registering FragmentTTIReceiver properly")
    }
}


/// Adding ability to override preconditionFailure in tests
dynamic func preconditionFailure(_ message: String, file: StaticString = #file, line: UInt = #line) {
    Swift.preconditionFailure(message, file: file, line: line)
}


/// Type eraser class, that allows us to use existential protocols for FragmentReceiver
class AnyFragmentTTIReporter: AppMetricsReporter {
    init<F>(reporter: FragmentTTIReporter<F>) {
        _start = { (identifier: Any) in
            guard let identifier = identifier as? F.FragmentIdentifier else {
                return EmptyFragmentTTITrackable()
            }
            return reporter.start(identifier: identifier)
        }
    }
    private let _start: (Any) -> FragmentTTITrackable

    func start<FragmentIdentifier>(identifier: FragmentIdentifier) -> FragmentTTITrackable {
        _start(identifier)
    }
}
