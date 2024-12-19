//
//  PerformanceMonitoring.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 05/07/2021.
//

import UIKit


/// This is a base protocol for recievers of the metrics from AppMetricsReporter's,
/// those metrics are not connected to some particular UIViewController.
public protocol AppMetricsReceiver {}


/// This is a protocol for classes,
/// which report metrics without any view controller observer
protocol AppMetricsReporter: AnyObject {}

public struct Experiments {
    public init() {}
}

public enum PerformanceMonitoring {

    private(set) static var appReporters: [AppMetricsReporter] = []
    private static let lock = NSLock()
    private static var viewControllerSubscriberEnabled = false
    static var experiments = Experiments()


    /// Method to start PerformanceSuite
    /// - Parameters:
    ///   - config: By passing config you are enabling or disabling some parts of the PerformanceSuite
    ///   - storage: Simple key/value storage which we use to store some simple objects, by default `UserDefaults` is used.
    ///   - didCrashPreviously: flag if app crashed during previous launch. For example, you can pass `FIRCrashlytics.crashlytics.didCrashDuringPreviousExecution` if you use Firebase for crash reporting. If you pass `false`, all the crashes will be considered as memory terminations.
    ///   - experiments: Feature flags that can be used to enable/disable some experimentation features inside PerformanceSuite. Is used for A/B testing in production.
    ///   NB: If you use `FIRCrashlytics.crashlytics.didCrashDuringPreviousExecution`, do not forget, to call FirebaseApp.configure() before that,
    ///   otherwise it will be always `false`.
    public static func enable(
        config: Config = [],
        storage: Storage = UserDefaults.standard,
        didCrashPreviously: Bool = false,
        experiments: Experiments = Experiments()
    ) throws {
        lock.lock()
        defer {
            lock.unlock()
        }

        Self.experiments = experiments

        guard self.appReporters.isEmpty && !viewControllerSubscriberEnabled else {
            assertionFailure("You cannot call `enable` twice. Should `disable` before that.")
            return
        }

        let (vcObservers, appReporters) = makeObservers(config: config, storage: storage, didCrashPreviously: didCrashPreviously)
        if !vcObservers.isEmpty {
            let observersCollection = ViewControllerObserverCollection(observers: vcObservers)
            try ViewControllerSubscriber().subscribeObserver(observersCollection)
        }
        self.appReporters = appReporters
        self.viewControllerSubscriberEnabled = !vcObservers.isEmpty
    }


    /// Method to stop PerformanceSuite monitoring.
    public static func disable() throws {
        lock.lock()
        defer {
            lock.unlock()
        }
        if viewControllerSubscriberEnabled {
            try ViewControllerSubscriber().unsubscribeObservers()
        }

        appReporters = []
        viewControllerSubscriberEnabled = false
        experiments = Experiments()
    }


    /// Call this method in the beginning of `main()` function of your app if you track startup time and want to track
    /// pre-main and main time separately inside the startup time.
    ///
    /// Also, you need to call this method to detect app sessions with pre-warming.
    public static func onMainStarted() {
        StartupTimeReporter.recordMainStarted()
        AppInfoHolder.recordMainStarted()
        #if arch(arm64)
            // if this function is called - save main thread mach port here, before performance suite is initialized
            precondition(Thread.isMainThread)
            MainThreadCallStack.storeMainThread()
        #endif
    }

    /// This method will start TTI measurement from the moment of the call.
    /// - Parameter identifier: string identifier of your fragment.
    /// - Returns: trackable fragment object, you will need to call `fragmentIsReady` on this object to finish TTI tracking.
    public static func startFragmentTTI<FragmentIdentifier>(identifier: FragmentIdentifier) -> FragmentTTITrackable {
        lock.lock()
        defer {
            lock.unlock()
        }
        if let reporter = appReporters.compactMap({ $0 as? AnyFragmentTTIReporter }).first {
            return reporter.start(identifier: identifier)
        } else {
            return EmptyFragmentTTITrackable()
        }
    }


    /// The information about the recent app start
    public static var appStartInfo: AppStartInfo {
        return AppInfoHolder.appStartInfo
    }

    private static func makeTTIObserverFactory<T: TTIMetricsReceiver>(metricsReceiver: T) -> any ViewControllerObserver {
        return ViewControllerObserverFactory<TTIObserver, T>(metricsReceiver: metricsReceiver) { screen in
            TTIObserver(screen: screen, metricsReceiver: metricsReceiver)
        }
    }

    private static func appendTTIObservers(config: Config, vcObservers: inout [ViewControllerObserver]) {
        guard let screenTTIReceiver = config.screenTTIReceiver else {
            return
        }
        let ttiFactory = makeTTIObserverFactory(metricsReceiver: screenTTIReceiver)
        vcObservers.append(ttiFactory)
    }

    private static func makeRenderingObserverFactory<R: RenderingMetricsReceiver>(metricsReceiver: R, framesMeter: FramesMeter) -> any ViewControllerObserver {
        return ViewControllerObserverFactory<RenderingObserver, R>(metricsReceiver: metricsReceiver) { screen in
            RenderingObserver(screen: screen, metricsReceiver: metricsReceiver, framesMeter: framesMeter)
        }
    }

    private static func appendRenderingObservers(
        config: Config, vcObservers: inout [ViewControllerObserver], appReporters: inout [AppMetricsReporter]
    ) {
        guard config.renderingEnabled else {
            return
        }
        let framesMeter = DefaultFramesMeter()

        if let screenRenderingReceiver = config.screenRenderingReceiver {
            let renderingFactory = makeRenderingObserverFactory(metricsReceiver: screenRenderingReceiver, framesMeter: framesMeter)
            vcObservers.append(renderingFactory)
        }

        if let appRenderingReceiver = config.appRenderingReceiver {
            #if PERFORMANCE_TESTS
                // we reduce throttle interval to send app rendering metrics more often, so we do not loose them when UI test finished
                let appRenderingReporter = AppRenderingReporter(
                    metricsReceiver: appRenderingReceiver, framesMeter: framesMeter, sendingThrottleInterval: 0.3)
            #else
                let appRenderingReporter = AppRenderingReporter(metricsReceiver: appRenderingReceiver, framesMeter: framesMeter)
            #endif
            appReporters.append(appRenderingReporter)
        }
    }

    private static func appendStartupObservers(
        config: Config, vcObservers: inout [ViewControllerObserver], appReporters: inout [AppMetricsReporter]
    ) -> StartupProvider? {
        guard let startupTimeReceiver = config.startupTimeReceiver else {
            return nil
        }
        let startupTimeReporter = StartupTimeReporter(receiver: startupTimeReceiver)
        let startupTimeObserver = startupTimeReporter.makeViewControllerObserver()
        appReporters.append(startupTimeReporter)
        vcObservers.append(startupTimeObserver)
        return startupTimeReporter
    }

    private static func appendWatchdogTerminationsObserver(
        config: Config, dependencies: TerminationDependencies, didHangPreviouslyProvider: DidHangPreviouslyProvider?,
        appReporters: inout [AppMetricsReporter]
    ) {
        guard let watchdogTerminationsReceiver = config.watchdogTerminationsReceiver else {
            return
        }

        if let startupProvider = dependencies.startupProvider {
            let watchdogTerminationsReporter = WatchdogTerminationReporter(storage: dependencies.storage,
                                                                           didCrashPreviously: dependencies.didCrashPreviously,
                                                                           didHangPreviouslyProvider: didHangPreviouslyProvider,
                                                                           startupProvider: startupProvider,
                                                                           receiver: watchdogTerminationsReceiver)
            appReporters.append(watchdogTerminationsReporter)
        } else {
            fatalError("Startup time reporting is needed to enable watchdog terminations reporting. Please pass `.startupTime(_)` in the config.")
        }
    }

    private static func appendHangObservers(
        config: Config,
        dependencies: TerminationDependencies,
        appReporters: inout [AppMetricsReporter]
    ) -> DidHangPreviouslyProvider? {
        guard let hangsReceiver = config.hangsReceiver else {
            return nil
        }
        if let startupProvider = dependencies.startupProvider {
            precondition(hangsReceiver.hangThreshold > 0)
            let hangTreshold = DispatchTimeInterval.timeInterval(hangsReceiver.hangThreshold)
            let detectionTimerInterval = DispatchTimeInterval.timeInterval(hangsReceiver.hangThreshold / 2)
            let hangReporter = HangReporter(storage: dependencies.storage,
                                            startupProvider: startupProvider,
                                            detectionTimerInterval: detectionTimerInterval,
                                            hangThreshold: hangTreshold,
                                            didCrashPreviously: dependencies.didCrashPreviously,
                                            receiver: hangsReceiver)
            appReporters.append(hangReporter)

            #if arch(arm64)
                DispatchQueue.main.async {
                    // if `PerformanceMonitoring.onMainStarted` wasn't called, save mach port at least here.
                    MainThreadCallStack.storeMainThread()
                }
            #endif
            return hangReporter
        } else {
            fatalError("Startup time reporting is needed to enable hangs reporting. Please pass `.startupTime(_)` in the config.")
        }
    }

    private static func appendLeaksObservers(config: Config, vcObservers: inout [ViewControllerObserver]) {
        guard let leaksReceiver = config.viewControllerLeaksReceiver else {
            return
        }
        let leaksObserver = ViewControllerLeaksObserver(metricsReceiver: leaksReceiver)
        vcObservers.append(leaksObserver)
    }

    private static func makeLoggingObserverFactory<V: ViewControllerLoggingReceiver>(metricsReceiver: V) -> any ViewControllerObserver {
        return ViewControllerObserverFactory<LoggingObserver, V>(metricsReceiver: metricsReceiver) { screen in
            LoggingObserver(screen: screen, receiver: metricsReceiver)
        }
    }

    private static func makeLastScreenObserver() -> any ViewControllerObserver {
        return LastOpenedScreenObserver()
    }

    private static func appendLoggingObservers(config: Config, vcObservers: inout [ViewControllerObserver]) {
        guard let loggingReceiver = config.loggingReceiver else {
            return
        }
        let loggingFactory = makeLoggingObserverFactory(metricsReceiver: loggingReceiver)
        vcObservers.append(loggingFactory)
        vcObservers.append(makeLastScreenObserver())
    }

    private static func makeFragmentTTIReporter<F: FragmentTTIMetricsReceiver>(metricsReceiver: F) -> AppMetricsReporter {
        return AnyFragmentTTIReporter(reporter: FragmentTTIReporter(metricsReceiver: metricsReceiver))
    }

    private static func appendFragmentTTIReporter(config: Config, appReporters: inout [AppMetricsReporter]) {
        guard let fragmentTTIReceiver = config.fragmentTTIReceiver else {
            return
        }
        let fragmentTTIReporter = makeFragmentTTIReporter(metricsReceiver: fragmentTTIReceiver)
        appReporters.append(fragmentTTIReporter)
    }

    private static func makeObservers(config: Config, storage: Storage, didCrashPreviously: Bool) -> (
        [ViewControllerObserver], [AppMetricsReporter]
    ) {
        var vcObservers = [ViewControllerObserver]()
        var appReporters = [AppMetricsReporter]()

        appendTTIObservers(config: config, vcObservers: &vcObservers)
        appendRenderingObservers(config: config, vcObservers: &vcObservers, appReporters: &appReporters)
        let startupProvider = appendStartupObservers(config: config, vcObservers: &vcObservers, appReporters: &appReporters)
        let deps = TerminationDependencies(startupProvider: startupProvider, storage: storage, didCrashPreviously: didCrashPreviously)

        let didHangPreviouslyProvider = appendHangObservers(
            config: config,
            dependencies: deps,
            appReporters: &appReporters
        )
        appendWatchdogTerminationsObserver(
            config: config,
            dependencies: deps,
            didHangPreviouslyProvider: didHangPreviouslyProvider,
            appReporters: &appReporters
        )
        appendLeaksObservers(config: config, vcObservers: &vcObservers)
        appendLoggingObservers(config: config, vcObservers: &vcObservers)
        appendFragmentTTIReporter(config: config, appReporters: &appReporters)

        return (vcObservers, appReporters)
    }


    /// This method might be used in tests to replace `PerformanceMonitoring.queue` with the main queue and after the test revert it back.
    /// It might be useful in tests, where you test methods which should be called from `PerformanceMonitoring.queue`.
    /// - Parameter newQueue: new queue to set as `PerformanceMonitoring.queue`
    /// - Returns:old queue, which was replaced
    @discardableResult
    static func changeQueueForTests(_ newQueue: DispatchQueue) -> DispatchQueue {
        let oldQueue = queue
        queue = newQueue
        return oldQueue
    }

    /// This queue is used for all the monitoring logic. It is interactive because we should react faster for proper measurements
    /// It is `var`, not `let` only to be able to replace it in tests. Do not change it in production.
    static private(set) var queue = DispatchQueue(label: "performance_suite_monitoring_queue", qos: .userInteractive)

    /// This queue is used to send data to the consumer. It is background because we don't need to be fast there
    static let consumerQueue = DispatchQueue(label: "performance_suite_consumer_queue", qos: .background)
}

private struct TerminationDependencies {
    let startupProvider: StartupProvider?
    let storage: Storage
    let didCrashPreviously: Bool
}
