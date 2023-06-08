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

public protocol FragmentTTIMetricsReceiver: AnyObject {
    func fragmentTTIMetricsReceived(metrics: TTIMetrics, identifier: String)
}

private class Trackable: FragmentTTITrackable {

    private let identifier: String
    private let timeProvider: TimeProvider
    private let metricsReceiver: FragmentTTIMetricsReceiver
    private let appStateObserver: AppStateObserver
    private weak var reporter: FragmentTTIReporter?

    private let createdTime: DispatchTime
    private var isRenderedTime: DispatchTime?
    private var ttiCalculated = false


    init(
        identifier: String,
        timeProvider: TimeProvider,
        metricsReceiver: FragmentTTIMetricsReceiver,
        appStateObserver: AppStateObserver,
        reporter: FragmentTTIReporter
    ) {
        self.identifier = identifier
        self.timeProvider = timeProvider
        self.metricsReceiver = metricsReceiver
        self.appStateObserver = appStateObserver
        self.reporter = reporter
        self.createdTime = timeProvider.now()
    }

    func fragmentIsRendered() {
        let now = timeProvider.now()
        PerformanceSuite.queue.async {
            self.isRenderedTime = now
        }
    }

    func fragmentIsReady() {
        let now = timeProvider.now()
        PerformanceSuite.queue.async {
            self.reportTTI(now: now)
        }
    }

    private func reportTTI(now: DispatchTime) {
        dispatchPrecondition(condition: .onQueue(PerformanceSuite.queue))
        if ttiCalculated {
            // consecutive calls of `fragmentIsReady` shouldn't send anything
            return
        }

        if appStateObserver.wasInBackground {
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
        PerformanceSuite.consumerQueue.async {
            self.metricsReceiver.fragmentTTIMetricsReceived(metrics: metrics, identifier: self.identifier)
        }

        ttiCalculated = true
    }
}

class FragmentTTIReporter: AppMetricsReporter {

    init(
        metricsReceiver: FragmentTTIMetricsReceiver, timeProvider: TimeProvider = defaultTimeProvider,
        appStateObserverFactory: @escaping () -> AppStateObserver = { DefaultAppStateObserver() }
    ) {
        self.metricsReceiver = metricsReceiver
        self.timeProvider = timeProvider
        self.appStateObserverFactory = appStateObserverFactory
    }

    private let metricsReceiver: FragmentTTIMetricsReceiver
    private let timeProvider: TimeProvider
    private let appStateObserverFactory: () -> AppStateObserver

    func start(identifier: String) -> FragmentTTITrackable {
        let fragment = Trackable(
            identifier: identifier,
            timeProvider: timeProvider,
            metricsReceiver: metricsReceiver,
            appStateObserver: appStateObserverFactory(),
            reporter: self)
        return fragment
    }
}

/// Stub trackable object which is returned in case no FragmentTTIReporter is registered
class EmptyFragmentTTITrackable: FragmentTTITrackable {
    func fragmentIsReady() {
        preconditionFailure("You've called startFragmentTTI without registering FragmentTTIReceiver")
    }
    func fragmentIsRendered() {
        preconditionFailure("You've called startFragmentTTI without registering FragmentTTIReceiver")
    }
}


/// Adding ability to override preconditionFailure in tests
dynamic func preconditionFailure(_ message: String, file: StaticString = #file, line: UInt = #line) {
    Swift.preconditionFailure(message, file: file, line: line)
}
