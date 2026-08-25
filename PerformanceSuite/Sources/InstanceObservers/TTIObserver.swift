//
//  TTIObserver.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 06/07/2021.
//

import UIKit

/// Observer that calculates `TTIMetrics` during view controller lifetime.
final class TTIObserver<T: TTIMetricsReceiver>: ViewControllerInstanceObserver, ScreenIsReadyProvider {

    init(screen: T.ScreenIdentifier,
         metricsReceiver: T,
         timeProvider: TimeProvider = defaultTimeProvider,
         appStateListener: AppStateListener = DefaultAppStateListener()
    ) {
        self.screen = screen
        self.metricsReceiver = metricsReceiver
        self.timeProvider = timeProvider
        self.appStateListener = appStateListener
        registerAppLifecycleObserver()
    }

    private let screen: T.ScreenIdentifier
    private let metricsReceiver: T
    private let timeProvider: TimeProvider
    private let appStateListener: AppStateListener


    private var screenCreatedTime: DispatchTime?
    private var viewDidAppearTime: DispatchTime?
    private var viewWillAppearTime: DispatchTime?
    private var screenIsReadyTime: DispatchTime?
    private var ttiCalculated = false
    private var sameRunLoopAsTheInit = false
    private var ignoreThisScreen = false

    private var customCreationTime: DispatchTime?

    /// Live measurement handle from `screenTTIMeasurementStarted`, held on `PerformanceMonitoring.queue`. Handed
    /// back at `screenTTIMeasurementEnded`. No path may leave it non-nil, or the span is left open for the
    /// backend to auto-terminate.
    private var measurementHandle: (any MeasurementHandle)?

    /// The swizzler defers `viewWillAppear`/`viewDidAppear` through `main.async` but calls
    /// `viewWillDisappear` directly, so a same-turn push-then-pop lands the disappear first. Mirrors
    /// `RenderingObserver`. Set/read only on `PerformanceMonitoring.queue`.
    private var didAppearProcessed = false
    private var pendingDisappear = false

    /// `upcomingCustomCreationTime` is a process-global. An abandoned screen that leaves it set strands it
    /// for the next screen, which then reports a TTI anchored before its own `init`.
    private var consumedCustomCreationTime = false

    /// Block-based app-lifecycle observer (`TTIObserver` is generic, so it cannot expose @objc selectors).
    /// Removed in `deinit`.
    private var lifecycleObserver: (any NSObjectProtocol)?

    func beforeInit() {
        let now = timeProvider.now()
        let action = {
            self.sameRunLoopAsTheInit = true
            assert(!self.ttiCalculated)
            assert(self.screenCreatedTime == nil)
            self.screenCreatedTime = now

            // set flag to false in the next main run loop. For that switch back to main queue, and again to our queue
            DispatchQueue.main.async {
                PerformanceMonitoring.queue.async {
                    self.sameRunLoopAsTheInit = false
                }
            }
        }
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        action()
    }

    func beforeViewDidLoad() {
        // if there is time passed between `init` and `viewDidLoad`, it means view controller was created earlier, but displayed only recently,
        // in this case we don't consider `init` time, but start measuring in `viewDidLoad`.
        // Ideally we should start before `loadView`, but it is impossible to swizzle `loadView` because usually nobody calls `super.loadView`
        // in their custom implementations. So we start at `viewDidLoad` as the nearest possible place to swizzle.
        let now = timeProvider.now()
        let action = {
            if !self.sameRunLoopAsTheInit {
                assert(!self.ttiCalculated)
                self.screenCreatedTime = now
            }
            // Guard on `measurementHandle == nil` (not just `ttiCalculated`): after a report clears
            // measurementHandle but sets ttiCalculated, a re-entrant beforeViewDidLoad must not start a
            // second orphaned measurement. `ignoreThisScreen` covers the double-viewWillAppear cancel path.
            if !self.ttiCalculated && !self.ignoreThisScreen && self.measurementHandle == nil,
               #available(iOS 16.0, *),
               let live = self.metricsReceiver as? any LiveTTIMetricsReceiver<T.ScreenIdentifier> {
                self.measurementHandle = live.screenTTIMeasurementStarted(screen: self.screen)
            }
        }
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        action()
    }

    func afterViewWillAppear() {
        let now = timeProvider.now()
        let action = {
            if self.viewWillAppearTime != nil && self.ttiCalculated == false {
                // viewWillAppear might be called twice before viewDidAppear
                // One example: when we show view controller in UINavigationController
                // and instantly after that push another controller without animation.
                // In this case we will have such events:
                //
                // init -> viewDidLoad -> viewWillAppear -> user spent time on another screen, user goes back
                // -> viewWillAppear -> viewDidAppear
                //
                // For such cases we can't calculate anything, just ignore it.
                self.ignoreThisScreen = true
                self.cancelMeasurement()
            }

            // Consumed whether or not a metric is still permitted; only the assignment is gated.
            if !self.consumedCustomCreationTime {
                self.consumedCustomCreationTime = true
                let upcoming = TTIObserverHelper.upcomingCustomCreationTime
                TTIObserverHelper.upcomingCustomCreationTime = nil
                if self.shouldReportTTI {
                    self.customCreationTime = upcoming
                }
            }

            if self.shouldReportTTI && self.viewWillAppearTime == nil {
                self.viewWillAppearTime = now
            }
        }

        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        action()
    }

    func afterViewDidAppear() {
        let now = timeProvider.now()
        let action = {
            if self.shouldReportTTI && self.viewDidAppearTime == nil {
                self.viewDidAppearTime = now
                self.reportTTIIfNeeded()
            }
            // Unconditional: `processDisappear` distinguishes "not drained yet" from "never appeared".
            self.didAppearProcessed = true
            if self.pendingDisappear {
                self.pendingDisappear = false
                self.processDisappear()
            }
        }

        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        action()
    }

    func beforeViewWillDisappear() {
        let action = {
            guard self.didAppearProcessed else {
                // Replayed from `afterViewDidAppear`. A screen that truly never appears never gets there, and
                // its span is released by `handleWillResignActive` or `deinit` instead.
                self.pendingDisappear = true
                return
            }
            self.processDisappear()
        }

        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        action()
    }

    private func processDisappear() {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))

        // No metric is permitted and none ever will be.
        guard shouldReportTTI else {
            cancelMeasurement()
            return
        }
        // didAppear has been processed, so nil here really does mean the screen never appeared — e.g. a
        // container that touched `view` on an off-screen child. Latched so a late `screenIsReady()` cannot
        // resurrect the cancelled measurement.
        guard viewDidAppearTime != nil else {
            ignoreThisScreen = true
            cancelMeasurement()
            return
        }
        if screenIsReadyTime == nil {
            // if screenIsReady wasn't called until now, we consider that screen was ready in `viewDidAppear`.
            screenIsReadyTime = viewDidAppearTime
        }
        reportTTIIfNeeded()
    }

    static var identifier: AnyObject {
        return TTIObserverHelper.identifier
    }

    func screenIsReady() {
        let now = timeProvider.now()
        PerformanceMonitoring.queue.async {
            if self.shouldReportTTI && self.screenIsReadyTime == nil {
                self.screenIsReadyTime = now
                self.reportTTIIfNeeded()
            }
        }
    }

    private func reportTTIIfNeeded() {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))

        guard shouldReportTTI,
            let screenCreatedTime,
            let viewWillAppearTime,
            let viewDidAppearTime,
            let screenIsReadyTime
        else {
            return
        }

        let ttiStartTime = customCreationTime ?? screenCreatedTime
        let ttiEndTime = max(screenIsReadyTime, viewDidAppearTime)
        let tti = ttiStartTime.distance(to: ttiEndTime)
        if tti < .zero {
            assertionFailure("We received negative TTI  for \(screen). That should never happen")
            cancelMeasurement()
            return
        }

        // TTFR should be measuring time only when controller is already alive, so we ignore `customCreationTime` if it happened before `init`.
        let ttfrStartTime = max(screenCreatedTime, ttiStartTime)
        let ttfrEndTime = viewWillAppearTime
        let ttfr = ttfrStartTime.distance(to: ttfrEndTime)
        if ttfr < .zero {
            assertionFailure("We received negative TTFR  for \(screen). That should never happen")
            cancelMeasurement()
            return
        }


        let metrics = TTIMetrics(tti: tti, ttfr: ttfr, appStartInfo: AppInfoHolder.appStartInfo)
        let context = self.measurementHandle
        self.measurementHandle = nil
        PerformanceMonitoring.consumerQueue.async {
            if #available(iOS 16.0, *), let live = self.metricsReceiver as? any LiveTTIMetricsReceiver<T.ScreenIdentifier> {
                live.screenTTIMeasurementEnded(metrics: metrics, screen: self.screen, context: context)
            } else {
                self.metricsReceiver.ttiMetricsReceived(metrics: metrics, screen: self.screen)
            }
        }

        self.ttiCalculated = true
    }

    private var shouldReportTTI: Bool {
        return !ttiCalculated && !appStateListener.wasInBackground && !ignoreThisScreen
    }

    /// Backgrounding fires no `viewWillDisappear`, so without this an unresolved span is left for the backend
    /// to auto-terminate. No `didBecomeActive` restart, unlike `RenderingObserver`: TTI is one-shot.
    private func registerAppLifecycleObserver() {
        lifecycleObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.handleWillResignActive()
        }
    }

    private func handleWillResignActive() {
        // Synchronous, so the span closes before the backend ends the session. Deliberately not gated on
        // `shouldReportTTI`: `DefaultAppStateListener` registers its observer in an `init` that runs as this
        // observer's default argument, so `wasInBackground` is already true here and a gate would be dead code.
        PerformanceMonitoring.runOnQueue {
            self.ignoreThisScreen = true
            self.cancelMeasurement()
        }
    }

    /// Cancel and clear the open live measurement. Called from every abandon path. Idempotent.
    private func cancelMeasurement() {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        if let context = self.measurementHandle {
            context.cancel()
            self.measurementHandle = nil
        }
    }

    deinit {
        if let lifecycleObserver {
            NotificationCenter.default.removeObserver(lifecycleObserver)
        }
        // VC went away before TTI completed: discard any open measurement. measurementHandle is mutated only on
        // PerformanceMonitoring.queue and queued closures retain self, so deinit runs only after
        // that work drains — direct access is race-free.
        self.measurementHandle?.cancel()
    }
}

/// Non-generic helper for generic `TTIObserver`. To put all the static methods and vars there.
final class TTIObserverHelper {
    static var upcomingCustomCreationTime: DispatchTime?
    static func startCustomCreationTime(timeProvider: TimeProvider = defaultTimeProvider) {
        let now = timeProvider.now()
        PerformanceMonitoring.queue.async {
            upcomingCustomCreationTime = now
        }
    }

    static func clearCustomCreationTime() {
        PerformanceMonitoring.queue.async {
            upcomingCustomCreationTime = nil
        }
    }

    static let identifier: AnyObject = NSObject()
}

protocol ScreenIsReadyProvider {
    func screenIsReady()
}
