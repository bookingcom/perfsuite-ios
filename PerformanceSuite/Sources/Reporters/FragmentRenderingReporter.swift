//
//  FragmentRenderingReporter.swift
//  PerformanceSuite
//
//  Created by Luis Resende on 12/10/2026.
//

import Foundation

/// Object returned from `PerformanceMonitoring.startFragmentRendering`.
/// Call `fragmentRenderingFinished()` when the fragment is no longer visible to report rendering metrics.
public protocol FragmentRenderingTrackable: AnyObject {
    func fragmentRenderingFinished()
}

/// Implement this protocol to receive fragment-level rendering metrics (freeze time, session duration, etc.).
public protocol FragmentRenderingMetricsReceiver<FragmentIdentifier>: AnyObject {
    /// It is kept and passed to receivers off main, so it must reference a view controller only weakly, and adopt
    /// `ViewControllerReferencing` then.
    associatedtype FragmentIdentifier
    func fragmentRenderingMetricsReceived(metrics: RenderingMetrics, fragment: FragmentIdentifier)
}

/// Opt-in live-measurement variant of ``FragmentRenderingMetricsReceiver``.
/// The reporter starts a measurement when the trackable is vended and ends it when
/// `fragmentRenderingFinished` fires; `cancel()` covers abandonment. Requires iOS 16.
public protocol LiveFragmentRenderingMetricsReceiver<FragmentIdentifier>: FragmentRenderingMetricsReceiver {
    func fragmentRenderingStarted(fragment: FragmentIdentifier) -> (any MeasurementHandle)?
    func fragmentRenderingEnded(
        metrics: RenderingMetrics,
        fragment: FragmentIdentifier,
        context: (any MeasurementHandle)?
    )
}

private class Trackable<F: FragmentRenderingMetricsReceiver>: FragmentRenderingTrackable, FramesMeterReceiver {

    private let identifier: ReceiverIdentifier<F.FragmentIdentifier>
    private let metricsReceiver: F
    private let framesMeter: FramesMeter
    private let appStateListener: AppStateListener

    private var metrics = RenderingMetrics.zero
    private var finished = false
    private var measurementHandle: (any MeasurementHandle)?

    init(
        identifier: F.FragmentIdentifier,
        metricsReceiver: F,
        framesMeter: FramesMeter,
        appStateListener: AppStateListener
    ) {
        self.identifier = ReceiverIdentifier(identifier)
        self.metricsReceiver = metricsReceiver
        self.framesMeter = framesMeter
        self.appStateListener = appStateListener

        PerformanceMonitoring.queue.async {
            self.metrics = .zero
            self.framesMeter.subscribe(receiver: self)
        }

        if #available(iOS 16.0, *), let live = metricsReceiver as? any LiveFragmentRenderingMetricsReceiver<F.FragmentIdentifier> {
            self.measurementHandle = self.identifier.withIdentifier { live.fragmentRenderingStarted(fragment: $0) }
        }
    }

    func fragmentRenderingFinished() {
        PerformanceMonitoring.queue.async {
            self.reportMetrics()
        }
    }

    private func reportMetrics() {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        guard !finished else { return }
        finished = true

        framesMeter.unsubscribe(receiver: self)

        if appStateListener.wasInBackground {
            cancelMeasurement()
            return
        }

        let metrics = self.metrics
        let context = self.measurementHandle
        self.measurementHandle = nil

        let countersZero = RenderingMetrics.zero
        guard metrics != countersZero || context != nil else { return }

        PerformanceMonitoring.consumerQueue.async {
            let reported: Void? = self.identifier.withIdentifier { fragment in
                if #available(iOS 16.0, *), let live = self.metricsReceiver as? any LiveFragmentRenderingMetricsReceiver<F.FragmentIdentifier> {
                    live.fragmentRenderingEnded(metrics: metrics, fragment: fragment, context: context)
                } else {
                    self.metricsReceiver.fragmentRenderingMetricsReceived(metrics: metrics, fragment: fragment)
                }
            }
            if reported == nil, let context {
                self.identifier.retainingViewControllers { context.cancel() }
            }
        }
    }

    private func cancelMeasurement() {
        if let context = self.measurementHandle {
            identifier.retainingViewControllers { context.cancel() }
            self.measurementHandle = nil
        }
    }

    // MARK: - FramesMeterReceiver

    func frameTicked(frameDuration: CFTimeInterval, refreshRateDuration: CFTimeInterval) {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        let currentMetrics = RenderingMetrics.metrics(frameDuration: frameDuration, refreshRateDuration: refreshRateDuration)
        self.metrics = self.metrics + currentMetrics
    }

    deinit {
        if let context = measurementHandle {
            identifier.retainingViewControllers { context.cancel() }
        }
    }
}

class FragmentRenderingReporter<F: FragmentRenderingMetricsReceiver>: AppMetricsReporter {

    init(
        metricsReceiver: F,
        framesMeter: FramesMeter,
        appStateListenerFactory: @escaping () -> AppStateListener = { DefaultAppStateListener() }
    ) {
        self.metricsReceiver = metricsReceiver
        self.framesMeter = framesMeter
        self.appStateListenerFactory = appStateListenerFactory
    }

    private let metricsReceiver: F
    private let framesMeter: FramesMeter
    private let appStateListenerFactory: () -> AppStateListener

    func start(identifier: F.FragmentIdentifier) -> FragmentRenderingTrackable {
        Trackable(
            identifier: identifier,
            metricsReceiver: metricsReceiver,
            framesMeter: framesMeter,
            appStateListener: appStateListenerFactory()
        )
    }
}

class EmptyFragmentRenderingTrackable: FragmentRenderingTrackable {
    func fragmentRenderingFinished() {
        preconditionFailure("You've called startFragmentRendering without registering FragmentRenderingReceiver properly")
    }
}

class AnyFragmentRenderingReporter: AppMetricsReporter {
    init<F>(reporter: FragmentRenderingReporter<F>) {
        _start = { (identifier: Any) in
            guard let identifier = identifier as? F.FragmentIdentifier else {
                return EmptyFragmentRenderingTrackable()
            }
            return reporter.start(identifier: identifier)
        }
    }
    private let _start: (Any) -> FragmentRenderingTrackable

    func start<FragmentIdentifier>(identifier: FragmentIdentifier) -> FragmentRenderingTrackable {
        _start(identifier)
    }
}
