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
            }

            if self.shouldReportTTI && self.viewWillAppearTime == nil {
                self.customCreationTime = TTIObserverHelper.upcomingCustomCreationTime
                TTIObserverHelper.upcomingCustomCreationTime = nil

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
        }

        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        action()
    }

    func beforeViewWillDisappear() {
        // if screenIsReady wasn't called until now, we consider that screen was ready in `viewDidAppear`.
        let action = {
            if self.shouldReportTTI && self.screenIsReadyTime == nil {
                self.screenIsReadyTime = self.viewDidAppearTime
                self.reportTTIIfNeeded()
            }
        }

        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        action()
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
            return
        }

        // TTFR should be measuring time only when controller is already alive, so we ignore `customCreationTime` if it happened before `init`.
        let ttfrStartTime = max(screenCreatedTime, ttiStartTime)
        let ttfrEndTime = viewWillAppearTime
        let ttfr = ttfrStartTime.distance(to: ttfrEndTime)
        if ttfr < .zero {
            assertionFailure("We received negative TTFR  for \(screen). That should never happen")
            return
        }


        let metrics = TTIMetrics(tti: tti, ttfr: ttfr, appStartInfo: AppInfoHolder.appStartInfo)
        PerformanceMonitoring.consumerQueue.async {
            self.metricsReceiver.ttiMetricsReceived(metrics: metrics, screen: self.screen)
        }

        self.ttiCalculated = true
    }

    private var shouldReportTTI: Bool {
        return !ttiCalculated && !appStateListener.wasInBackground && !ignoreThisScreen
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
