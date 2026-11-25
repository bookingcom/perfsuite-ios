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


/// Implement this protocol if you want to receive events about Fragment TTI.
public protocol FragmentTTIMetricsReceiver<FragmentIdentifier>: AnyObject {
    /// This can be String, or enum or any other identifier
    /// It is kept and passed to receivers off main, so it must reference a view controller only weakly, and adopt
    /// `ViewControllerReferencing` then.
    associatedtype FragmentIdentifier

    /// Called on `consumerQueue` after `fragmentIsReady` fires on the trackable
    /// returned from `PerformanceMonitoring.startFragmentTTI`.
    func fragmentTTIMetricsReceived(metrics: TTIMetrics, fragment: FragmentIdentifier)
}

/// Opt-in live-measurement variant of ``FragmentTTIMetricsReceiver``. The reporter starts a measurement when the
/// trackable is vended and ends it when `fragmentIsReady` fires; `cancel()` covers abandonment.
/// Requires iOS 16.
public protocol LiveFragmentTTIMetricsReceiver<FragmentIdentifier>: FragmentTTIMetricsReceiver {
    func fragmentTTIMeasurementStarted(fragment: FragmentIdentifier) -> (any MeasurementHandle)?
    func fragmentTTIMeasurementEnded(
        metrics: TTIMetrics,
        fragment: FragmentIdentifier,
        context: (any MeasurementHandle)?
    )
}

private class Trackable<F: FragmentTTIMetricsReceiver>: FragmentTTITrackable {

    private let identifier: ReceiverIdentifier<F.FragmentIdentifier>
    private let timeProvider: TimeProvider
    private let metricsReceiver: F
    private let appStateListener: AppStateListener
    private weak var reporter: FragmentTTIReporter<F>?

    private let createdTime: DispatchTime
    private var isRenderedTime: DispatchTime?
    private var ttiCalculated = false

    /// Live measurement handle held across the trackable's lifetime. Mutated only on
    /// `PerformanceMonitoring.queue` after the initial assignment in `init`. Cancelled
    /// in `deinit` for the common abandonment path: caller never calls `fragmentIsReady()`.
    private var measurementHandle: (any MeasurementHandle)?

    init(
        identifier: F.FragmentIdentifier,
        timeProvider: TimeProvider,
        metricsReceiver: F,
        appStateListener: AppStateListener,
        reporter: FragmentTTIReporter<F>
    ) {
        self.identifier = ReceiverIdentifier(identifier)
        self.timeProvider = timeProvider
        self.metricsReceiver = metricsReceiver
        self.appStateListener = appStateListener
        self.reporter = reporter
        self.createdTime = timeProvider.now()
        // Start a live measurement synchronously on the caller's thread (matching createdTime) when the
        // receiver is live. iOS 16 only (constrained-existential cast); otherwise completed path.
        if #available(iOS 16.0, *), let live = metricsReceiver as? any LiveFragmentTTIMetricsReceiver<F.FragmentIdentifier> {
            self.measurementHandle = self.identifier.withIdentifier { live.fragmentTTIMeasurementStarted(fragment: $0) }
        }
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
            cancelMeasurement()
            return
        }


        let ttiStartTime = createdTime
        let ttiEndTime = now
        let tti = ttiStartTime.distance(to: ttiEndTime)
        if tti < .zero {
            assertionFailure("We received negative TTI  for \(identifierDescription) that should never happen")
            cancelMeasurement()
            return
        }

        let ttfrStartTime = createdTime
        // if `fragmentIsRendred` wasn't called, we take time of `fragmentIsReady` for TTFR end
        let ttfrEndTime = isRenderedTime ?? now
        let ttfr = ttfrStartTime.distance(to: ttfrEndTime)
        if ttfr < .zero {
            assertionFailure("We received negative TTFR  for \(identifierDescription) that should never happen")
            cancelMeasurement()
            return
        }

        let metrics = TTIMetrics(tti: tti, ttfr: ttfr, appStartInfo: AppInfoHolder.appStartInfo)
        let context = self.measurementHandle
        self.measurementHandle = nil
        PerformanceMonitoring.consumerQueue.async {
            let reported: Void? = self.identifier.withIdentifier { fragment in
                if #available(iOS 16.0, *), let live = self.metricsReceiver as? any LiveFragmentTTIMetricsReceiver<F.FragmentIdentifier> {
                    live.fragmentTTIMeasurementEnded(metrics: metrics, fragment: fragment, context: context)
                } else {
                    self.metricsReceiver.fragmentTTIMetricsReceived(metrics: metrics, fragment: fragment)
                }
            }
            if reported == nil, let context {
                self.identifier.retainingViewControllers { context.cancel() }
            }
        }

        ttiCalculated = true
    }

    private var identifierDescription: String {
        identifier.withIdentifier { "\($0)" } ?? "a deallocated fragment"
    }

    /// Cancel and clear the open live measurement. Idempotent.
    private func cancelMeasurement() {
        if let context = self.measurementHandle {
            identifier.retainingViewControllers { context.cancel() }
            self.measurementHandle = nil
        }
    }

    deinit {
        // Trackable dropped without `fragmentIsReady()`. Queued closures retain `self`,
        // so by deinit all queue work has drained — direct access is race-free.
        if let context = measurementHandle {
            identifier.retainingViewControllers { context.cancel() }
        }
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
