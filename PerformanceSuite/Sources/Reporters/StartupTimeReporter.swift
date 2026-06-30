//
//  StartupTimeReporter.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 29.03.2022
//


import UIKit

public struct StartupTimeData {

    ///                        user tapped icon ------------ main()----------------viewDidLoad-----------viewDidAppear (of the first View Controller)
    /// totalTime                      |-----------------------------------------------------------------------------|
    /// preMainTime                    |---------------------|
    /// mainTime                                             |-------------------------------------------------------|
    /// totalBeforeViewControllerTime  |------------------------------------------|
    /// mainBeforeViewControllerTime                         |--------------------|

    /// Time from app launched until `viewDidAppear` of the first view controller is finished.
    ///
    /// This is the most complete startup time which measures time from user tapped icon of the app until the first view controller is displayed on the screen.
    /// It will be a bit longer than Apple's measures of startup time, because Apple most probably records the end of Startup after the first call of `viewDidLayoutSubviews`
    /// of the first appeared view controller (https://medium.com/p/b5a66bd07c8c). But swizzling those calls will have too much overhead,
    /// that's why we finish the time in the first call of `viewDidAppear` method. And this actually makes more sense, since app is not interactive until the end of this call.
    public let totalTime: DispatchTimeInterval

    /// Time from app launched until  `main` function is called.
    ///
    /// In this time loading of dylibs, objective-c `load` and `initialize` methods and other stuff is included which is happening before `main` function is called.
    ///
    /// You need to call `PerformanceMonitoring.onMainStarted()` to track this time.
    public let preMainTime: DispatchTimeInterval?

    /// Time from `main` function is called until `viewDidAppear` of the first view controller is finished.
    ///
    /// `mainTime = totalTime - preMainTime`.
    /// You may want to monitor this time separately because this is the most controlled by developer part of startup time.
    ///
    /// You need to call `PerformanceMonitoring.onMainStarted()` to track this time.
    public let mainTime: DispatchTimeInterval?

    /// Time from app launched until `viewDidLoad` of the first view controller is called.
    ///
    /// You can use this value if you want to exclude most of TTI of the first view controller from startup time.
    /// So startup value will be measuring value before view controller is being created,
    /// and first view controller TTI will monitor remaining time.
    ///
    /// Ideally we should stop not on `viewDidLoad`, but when `init` is called for the first view controller,
    /// but some view controller can be created much earlier before displaying, so we decided to use `viewDidLoad`,
    /// since this method is most probably will be called when view controller is really displayed.
    public let totalBeforeViewControllerTime: DispatchTimeInterval

    /// Time from`main` function is called until `viewDidLoad` of the first view controller is called.
    ///
    /// You can use this value if you want to exclude most of TTI of the first view controller from startup time.
    /// So startup value will be measuring value before view controller is being created,
    /// and first view controller TTI will monitor remaining time.
    ///
    /// Ideally we should stop not on `viewDidLoad`, but when `init` is called for the first view controller,
    /// but some view controller can be created much earlier before displaying, so we decided to use `viewDidLoad`,
    /// since this method is most probably will be called when view controller is really displayed.
    ///
    /// `mainBeforeViewControllerTime = totalBeforeViewControllerTime - preMainTime`.
    /// You may want to monitor this time instead of `totalBeforeViewControllerTime` because this is the most controlled by developer part of startup time.
    ///
    /// You need to call `PerformanceMonitoring.onMainStarted()` to track this time.
    public let mainBeforeViewControllerTime: DispatchTimeInterval?

    /// Information about how app was started.
    /// You may want to ignore startup time events if app started after pre-warming or in background.
    public let appStartInfo: AppStartInfo
}

/// We need to know when app launch is finished in other reporters, for example in `HangReporter`.
/// We pass reference to `StartupTimeReporter` via this protocol.
protocol StartupProvider {
    var appIsStarting: Bool { get }

    func notifyAfterAppStarted(_ action: @escaping () -> Void)
}

final class StartupTimeReporter: AppMetricsReporter, StartupProvider {

    private let receiver: StartupTimeReceiver
    private let appStateListener: AppStateListener
    private let experiments: Experiments
    private var viewDidLoadTime: TimeInterval?
    private var isStarting = true
    private var onStartedActions: [() -> Void] = []

    // we store this value just after `main()` function started. In seconds since 1970.
    private static var mainStartedTime: TimeInterval?

    /// Live measurement handle from `receiver.startupMeasurementStarted()`, started in `init` and finalized at the
    /// first `viewDidAppear` (both on main). A live receiver may anchor it retroactively at process start.
    private var measurementHandle: (any MeasurementHandle)?

    init(
        receiver: StartupTimeReceiver,
        appStateListener: AppStateListener = DefaultAppStateListener(),
        experiments: Experiments = PerformanceMonitoring.experiments
    ) {
        self.receiver = receiver
        // Created here (during `enable()`, early in launch), so a `willResignActive` that arrives
        // before the first `viewDidAppear` latches `wasInBackground` for the drop check below.
        self.appStateListener = appStateListener
        self.experiments = experiments
        // Started runs synchronously on the caller's thread (typically main) right after
        // `recordMainStarted()`. Only a live receiver starts a measurement; others stay legacy.
        self.measurementHandle = (receiver as? LiveStartupTimeReceiver)?.startupMeasurementStarted()
    }

    /// This function should be called once just in the beginning of `main()` function of the app.
    /// This is not required. We won't have `preMainTime` and `mainTime`in `StartupTimeData` in case this function wasn't called.
    /// But we still will have `totalTime` there.
    static func recordMainStarted() {
        assert(Thread.isMainThread)
        assert(mainStartedTime == nil)
        mainStartedTime = currentTime()
    }

    /// Ability to forget recorded main time. Should be called only in tests
    static func forgetMainStartedForTests() {
        mainStartedTime = nil
    }

    func onViewDidLoadOfTheFirstViewController() {
        viewDidLoadTime = Self.currentTime()
    }

    /// This function will be called once after any view controller's `viewDidAppearTime`.
    func onViewDidAppearOfTheFirstViewController() {
        guard let viewDidLoadTime = viewDidLoadTime else {
            // This can happen, at least in XCTest,
            // that viewDidAppear is called for a view controller without viewDidLoad was called.
            // I reproduced this case in `PerformanceMonitoringTests.testIntegration` test.
            // Didn't see it in production though.
            // Discard the live measurement — startup measurement abandoned for this process.
            self.measurementHandle?.cancel()
            self.measurementHandle = nil
            return
        }

        if experiments.dropStartupTimeWhenAppWasInBackground, appStateListener.wasInBackground {
            // The app was sent to the background during startup, so the measured time includes
            // background time and would be misleadingly long. Drop the event — same rationale as
            // `TTIObserver` and `FragmentTTIReporter`. The app *did* finish starting, so we still
            // flip `isStarting` / fire `onStartedActions` below; only the receiver callback is suppressed.
            self.measurementHandle?.cancel()
            self.measurementHandle = nil
            markAppStarted()
            return
        }

        let viewDidAppearTime = Self.currentTime()
        let processStartTime = Self.processStartTime()

        let totalTimeInterval = viewDidAppearTime - processStartTime
        let totalTime = toDispatchInterval(totalTimeInterval)

        let totalBeforeViewControllerTimeInterval = viewDidLoadTime - processStartTime
        let totalBeforeViewControllerTime = toDispatchInterval(totalBeforeViewControllerTimeInterval)

        var preMainTime: DispatchTimeInterval?
        var mainTime: DispatchTimeInterval?
        var mainBeforeViewControllerTime: DispatchTimeInterval?
        if let mainStartedTime = Self.mainStartedTime {
            let preMainTimeInterval = mainStartedTime - processStartTime
            preMainTime = toDispatchInterval(preMainTimeInterval)

            let mainTimeInterval = viewDidAppearTime - mainStartedTime
            mainTime = toDispatchInterval(mainTimeInterval)

            let mainBeforeViewControllerTimeInterval = viewDidLoadTime - mainStartedTime
            mainBeforeViewControllerTime = toDispatchInterval(mainBeforeViewControllerTimeInterval)
        }

        let data = StartupTimeData(
            totalTime: totalTime,
            preMainTime: preMainTime,
            mainTime: mainTime,
            totalBeforeViewControllerTime: totalBeforeViewControllerTime,
            mainBeforeViewControllerTime: mainBeforeViewControllerTime,
            appStartInfo: AppInfoHolder.appStartInfo
        )
        let context = self.measurementHandle
        self.measurementHandle = nil
        PerformanceMonitoring.consumerQueue.async {
            if let live = self.receiver as? LiveStartupTimeReceiver {
                live.startupMeasurementEnded(data, context: context)
            } else {
                self.receiver.startupTimeReceived(data)
            }
        }

        markAppStarted()
    }

    /// Marks startup as finished: flips `isStarting` and fires any `notifyAfterAppStarted` actions.
    /// Runs regardless of whether the startup-time event itself was reported or dropped, so the
    /// startup-finished signal used by `HangReporter` / `WatchdogTerminationReporter` is unchanged.
    private func markAppStarted() {
        PerformanceMonitoring.queue.async {
            self.isStarting = false
            self.onStartedActions.forEach { $0() }
            self.onStartedActions.removeAll()
        }
    }

    deinit {
        // Defensive: cancel an unfinalized live measurement so it can't leak (e.g. reporter torn down in
        // tests before the first viewDidAppear). Idempotent.
        self.measurementHandle?.cancel()
    }

    func makeViewControllerObserver() -> ViewControllerObserver {
        return StartupTimeViewControllerObserver(reporter: self)
    }

    // MARK: - Time utils

    private static func processStartTime() -> TimeInterval {
        readProcessStartTime()
    }

    private static func currentTime() -> TimeInterval {
        return CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970
    }

    private func toDispatchInterval(_ timeInterval: TimeInterval) -> DispatchTimeInterval {
        let milliseconds = round(timeInterval * 1000)
        return DispatchTimeInterval.milliseconds(Int(milliseconds))
    }

    // MARK: - StartupProvider

    var appIsStarting: Bool {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        return isStarting
    }

    func notifyAfterAppStarted(_ action: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        if isStarting {
            onStartedActions.append(action)
        } else {
            action()
        }
    }
}

/// We need this observer to catch the first `viewWillAppear` call from the first appeared view controller.
final class StartupTimeViewControllerObserver: ViewControllerObserver {
    private let reporter: StartupTimeReporter
    private var viewDidLoadCalled = false
    private var viewDidAppearCalled = false

    init(reporter: StartupTimeReporter) {
        self.reporter = reporter
    }

    func beforeViewDidLoad(viewController: UIViewController) {
        guard !viewDidLoadCalled else {
            return
        }
        viewDidLoadCalled = true
        reporter.onViewDidLoadOfTheFirstViewController()
    }

    func afterViewDidAppear(viewController: UIViewController) {
        guard !viewDidAppearCalled else {
            return
        }
        viewDidAppearCalled = true
        reporter.onViewDidAppearOfTheFirstViewController()
    }

    func beforeInit(viewController: UIViewController) {}
    func afterViewWillAppear(viewController: UIViewController) {}
    func beforeViewWillDisappear(viewController: UIViewController) {}
    func beforeViewDidDisappear(viewController: UIViewController) {}
}
