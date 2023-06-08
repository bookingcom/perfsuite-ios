//
//  TTIObserver.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 06/07/2021.
//

import UIKit

/// Observer that calculates `TTIMetrics` during view controller lifetime.
final class TTIObserver: ViewControllerObserver {

    init(
        metricsReceiver: TTIMetricsReceiver, timeProvider: TimeProvider = defaultTimeProvider,
        appStateObserver: AppStateObserver = DefaultAppStateObserver()
    ) {
        self.metricsReceiver = metricsReceiver
        self.timeProvider = timeProvider
        self.appStateObserver = appStateObserver
    }

    private let metricsReceiver: TTIMetricsReceiver
    private let timeProvider: TimeProvider
    private let appStateObserver: AppStateObserver
    private weak var viewController: UIViewController?

    private var screenCreatedTime: DispatchTime?
    private var viewDidAppearTime: DispatchTime?
    private var viewWillAppearTime: DispatchTime?
    private var screenIsReadyTime: DispatchTime?
    private var ttiCalculated = false
    private var sameRunLoopAsTheInit = false
    private var ignoreThisScreen = false

    private static var upcomingCustomCreationTime: DispatchTime?
    private var customCreationTime: DispatchTime?

    static func startCustomCreationTime(timeProvider: TimeProvider = defaultTimeProvider) {
        let now = timeProvider.now()
        PerformanceSuite.queue.async {
            upcomingCustomCreationTime = now
        }
    }

    static func clearCustomCreationTime() {
        PerformanceSuite.queue.async {
            upcomingCustomCreationTime = nil
        }
    }

    func beforeInit(viewController: UIViewController) {
        let now = timeProvider.now()
        PerformanceSuite.queue.async {
            self.sameRunLoopAsTheInit = true
            assert(!self.ttiCalculated)
            assert(self.viewController == nil)
            assert(self.screenCreatedTime == nil)
            self.viewController = viewController
            self.screenCreatedTime = now

            // set flag to false in the next main run loop. For that switch back to main queue, and again to our queue
            DispatchQueue.main.async {
                PerformanceSuite.queue.async {
                    self.sameRunLoopAsTheInit = false
                }
            }
        }
    }

    func beforeViewDidLoad(viewController: UIViewController) {
        // if there is time passed between `init` and `viewDidLoad`, it means view controller was created earlier, but displayed only recently,
        // in this case we don't consider `init` time, but start measuring in `viewDidLoad`.
        // Ideally we should start before `loadView`, but it is impossible to swizzle `loadView` because usually nobody calls `super.loadView`
        // in their custom implementations. So we start at `viewDidLoad` as the nearest possible place to swizzle.
        let now = timeProvider.now()
        PerformanceSuite.queue.async {
            if !self.sameRunLoopAsTheInit {
                assert(!self.ttiCalculated)
                assert(viewController == self.viewController)
                self.screenCreatedTime = now
            }
        }
    }

    func afterViewWillAppear(viewController: UIViewController) {
        let now = timeProvider.now()
        PerformanceSuite.queue.async {
            assert(viewController == self.viewController)

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
                self.customCreationTime = Self.upcomingCustomCreationTime
                Self.upcomingCustomCreationTime = nil

                self.viewWillAppearTime = now
            }
        }
    }

    func afterViewDidAppear(viewController: UIViewController) {
        let now = timeProvider.now()
        PerformanceSuite.queue.async {
            assert(viewController == self.viewController)
            if self.shouldReportTTI && self.viewDidAppearTime == nil {
                self.viewDidAppearTime = now
                self.reportTTIIfNeeded()
            }
        }
    }

    func beforeViewWillDisappear(viewController: UIViewController) {
        // if screenIsReady wasn't called until now, we consider that screen was ready in `viewDidAppear`.
        PerformanceSuite.queue.async {
            if self.shouldReportTTI && self.screenIsReadyTime == nil {
                self.screenIsReadyTime = self.viewDidAppearTime
                self.reportTTIIfNeeded()
            }
        }
    }

    func beforeViewDidDisappear(viewController: UIViewController) {}

    func screenIsReady() {
        let now = timeProvider.now()
        PerformanceSuite.queue.async {
            if self.shouldReportTTI && self.screenIsReadyTime == nil {
                self.screenIsReadyTime = now
                self.reportTTIIfNeeded()
            }
        }
    }

    private func reportTTIIfNeeded() {
        dispatchPrecondition(condition: .onQueue(PerformanceSuite.queue))

        guard shouldReportTTI,
            let viewCreatedTime = screenCreatedTime,
            let viewWillAppearTime = viewWillAppearTime,
            let viewDidAppearTime = viewDidAppearTime,
            let screenIsReadyTime = screenIsReadyTime,
            let viewController = viewController
        else {
            return
        }

        let ttiStartTime = customCreationTime ?? viewCreatedTime
        let ttiEndTime = max(screenIsReadyTime, viewDidAppearTime)
        let tti = ttiStartTime.distance(to: ttiEndTime)
        if tti < .zero {
            assertionFailure("We received negative TTI  for \(viewController). That should never happen")
            return
        }

        // TTFR should be measuring time only when controller is already alive, so we ignore `customCreationTime` if it happened before `init`.
        let ttfrStartTime = max(viewCreatedTime, ttiStartTime)
        let ttfrEndTime = viewWillAppearTime
        let ttfr = ttfrStartTime.distance(to: ttfrEndTime)
        if ttfr < .zero {
            assertionFailure("We received negative TTFR  for \(viewController). That should never happen")
            return
        }


        let metrics = TTIMetrics(tti: tti, ttfr: ttfr, appStartInfo: AppInfoHolder.appStartInfo)
        PerformanceSuite.consumerQueue.async {
            self.metricsReceiver.ttiMetricsReceived(metrics: metrics, viewController: viewController)
        }

        self.ttiCalculated = true
    }

    private var shouldReportTTI: Bool {
        return !ttiCalculated && !appStateObserver.wasInBackground && !ignoreThisScreen
    }
}
