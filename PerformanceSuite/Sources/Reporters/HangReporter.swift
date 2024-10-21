//
//  HangsReporter.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 08/09/2021.
//

import Foundation
import UIKit

public protocol HangsReceiver: AnyObject {

    /// This method will be called on `PerformanceMonitoring.consumerQueue` just after the app launch for the fatal hangs,
    /// in case during the previous launch app was terminated during the main thread hang.
    /// - Parameter info: info related to the hang
    func fatalHangReceived(info: HangInfo)

    /// This method will be called on `PerformanceMonitoring.consumerQueue` after the main thread freeze resolved.
    /// - Parameter info: info related to the hang
    func nonFatalHangReceived(info: HangInfo)

    /// This method will be called on `PerformanceMonitoring.consumerQueue` just after the main thread is detected to be frozen.
    /// At this stage we do not know if this will be non-fatal or fatal hang. We just know, that some hang has started.
    ///
    /// We send `fatalHangReceived` events only after user re-launched the app after the fatal hang.
    /// If user has never launched the app after the hang, we won't receive such event. To track those
    /// users, you can track them in this method.
    func hangStarted(info: HangInfo)


    /// If the main thread doesn't respond for `hangThreshold`,
    /// we consider this as a start of a hang.
    ///
    /// After the main thread is back active, we log a hang as a non-fatal.
    /// If the main thread was never back active, we log as a fatal hang.
    ///
    /// Default value is 2 seconds.
    var hangThreshold: TimeInterval { get }
}

public extension HangsReceiver {
    var hangThreshold: TimeInterval {
        return 2
    }
}


/// WatchdogTerminationsReporter should know if app was killed because of the hang.
/// Providing this information via this protocol
protocol DidHangPreviouslyProvider: AnyObject {
    func didHangPreviously() -> Bool
}

protocol AppStateProvider: AnyObject {
    var applicationState: UIApplication.State { get }
}

extension UIApplication: AppStateProvider {}

/// Class is needed to observe fatal and non-fatal hangs in the app.
///
/// We call "the hang" any freeze of the main thread longer than `hangThreshold`.
/// Non-fatal hang is the hang that resolved and main thread continued to work.
/// Fatal hang is the hang that caused either system or the user to kill the app.
///
/// We schedule light operation on the main thread every second.
/// If it wasn't executed we consider this is a hang of the main thread.
final class HangReporter: AppMetricsReporter, DidHangPreviouslyProvider {

    private let storage: Storage
    private let timeProvider: TimeProvider
    private let startupProvider: StartupProvider
    private let workingQueue: DispatchQueue
    private let detectionTimer: DispatchSourceTimer
    private let detectionTimerInterval: DispatchTimeInterval
    private let didCrashPreviously: Bool
    private let enabledInDebug: Bool

    private var lastMainThreadDate: DispatchTime
    private var isSuspended = false
    private var startupIsHappening = true

    private let hangThreshold: DispatchTimeInterval

    private var willResignSubscription: AnyObject?
    private var didBecomeActiveSubscription: AnyObject?

    let receiver: HangsReceiver

    init(
        timeProvider: TimeProvider = DefaultTimeProvider(),
        storage: Storage = UserDefaults.standard,
        startupProvider: StartupProvider,
        appStateProvider: AppStateProvider = UIApplication.shared,
        workingQueue: DispatchQueue = PerformanceMonitoring.queue,
        detectionTimerInterval: DispatchTimeInterval,
        hangThreshold: DispatchTimeInterval,
        didCrashPreviously: Bool = false,
        enabledInDebug: Bool = false,
        receiver: HangsReceiver
    ) {
        self.timeProvider = timeProvider
        self.storage = storage
        self.startupProvider = startupProvider
        self.workingQueue = workingQueue
        self.detectionTimerInterval = detectionTimerInterval
        self.hangThreshold = hangThreshold
        self.didCrashPreviously = didCrashPreviously
        self.enabledInDebug = enabledInDebug
        self.receiver = receiver
        self.lastMainThreadDate = timeProvider.now()
        self.detectionTimer = DispatchSource.makeTimerSource(flags: .strict, queue: workingQueue)

        // when app started in background - we shouldn't start hang monitoring for sure
        // but when app is started with prewarming, applicationState is still .active,
        // so we are checking for 'appStartedWithPrewarming' flag here too.
        // We assume here, that if app is prewarmed, HangReporter will be created during this prewarming process,
        // because the whole PerformanceSuite should be started as early as possible.
        let prewarming = AppInfoHolder.appStartInfo.appStartedWithPrewarming
        let stateResolver = { appStateProvider.applicationState == .background || prewarming }
        let inBackground = Thread.isMainThread ? stateResolver() : DispatchQueue.main.sync { stateResolver() }

        self.workingQueue.async {
            // we check if last time app was killed during the hang
            self.notifyAboutFatalHangs()

            self.startupProvider.notifyAfterAppStarted { [weak self] in
                self?.workingQueue.async {
                    // startup finished, we reset the flag
                    self?.startupIsHappening = false
                    // we reset last date so we do not report hang which started during startup, but finished after startup finished
                    self?.lastMainThreadDate = timeProvider.now()
                }
            }

            self.start(inBackground: inBackground)
        }
    }

    private func start(inBackground: Bool) {
        lastMainThreadDate = timeProvider.now()
        scheduleDetectionTimer(inBackground: inBackground)
        subscribeToApplicationEvents()
    }

    private func scheduleDetectionTimer(inBackground: Bool) {
        detectionTimer.schedule(deadline: .now() + detectionTimerInterval, repeating: detectionTimerInterval)
        detectionTimer.setEventHandler { [weak self] in
            self?.detect()
        }
        if inBackground {
            isSuspended = true
        } else {
            detectionTimer.resume()
        }
    }

    private func notifyAboutFatalHangs() {
        guard let info = readAndClearHangInfo() else {
            return
        }
        guard !didCrashPreviously else {
            // if it crashed during hang, we do not report this as a hang, as it will be probably reported as a crash
            return
        }
#if DEBUG
        if !self.enabledInDebug {
            // In debug we can just pause on the breakpoint and this might be considered as a hang,
            // that's why in Debug we send events only in unit-tests. Or you may enable it manually to debug.
            return
        }
#endif
        PerformanceMonitoring.consumerQueue.async {
            self.receiver.fatalHangReceived(info: info)
        }
    }

    private func subscribeToApplicationEvents() {
        let operationQueue = OperationQueue()
        operationQueue.underlyingQueue = workingQueue
        didBecomeActiveSubscription = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: operationQueue
        ) { [weak self] _ in
            guard let self = self else {
                return
            }
            dispatchPrecondition(condition: .onQueue(self.workingQueue))
            if self.isSuspended {
                self.detectionTimer.resume()
                self.isSuspended = false
            }
            self.lastMainThreadDate = self.timeProvider.now()
        }

        willResignSubscription = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: operationQueue
        ) { [weak self] _ in
            guard let self = self else {
                return
            }
            dispatchPrecondition(condition: .onQueue(self.workingQueue))
            if !self.isSuspended {
                self.detectionTimer.suspend()
                self.isSuspended = true
            }
        }
    }

    private func detect() {
        dispatchPrecondition(condition: .onQueue(self.workingQueue))
        guard !isSuspended else {
            return
        }

        let hangInterval = currentHangInterval.milliseconds ?? 0
        let hangThreshold = hangThreshold.milliseconds ?? 0

        if var info = hangInfoInMemory {
            // we are already in hang, update duration and save to disk
            info.duration = currentHangInterval
            store(hangInfo: info)
        } else {
            // new hang detected - save the stack trace
            if hangInterval > hangThreshold {
                let callStack: String
#if arch(arm64)
                callStack = (try? MainThreadCallStack.readStack()) ?? ""
#else
                callStack = ""
#endif
                let info = HangInfo.with(callStack: callStack, duringStartup: startupIsHappening, duration: currentHangInterval)
                store(hangInfo: info)

#if DEBUG
                if !self.enabledInDebug {
                    // In debug we can just pause on the breakpoint and this might be considered as a hang,
                    // that's why in Debug we send events only in unit-tests. Or you may enable it manually to debug.
                    return
                }
#endif
                PerformanceMonitoring.consumerQueue.async {
                    // notify receiver, that hang has started
                    self.receiver.hangStarted(info: info)
                }
            }
        }

        DispatchQueue.main.async {
            self.workingQueue.async {
                self.onMainThreadIsActive()
            }
        }
    }

    private func onMainThreadIsActive() {
        if var info = hangInfoInMemory {
            // if detected the hang, main thread was unblocked, so this hang finished, this was non-fatal hang,
            // remove info about the hang and report non-fatal hang
            clearHangInfo()
            // we update hang with the proper duration
            info.duration = currentHangInterval
            PerformanceMonitoring.consumerQueue.async {
#if DEBUG
                if !self.enabledInDebug {
                    // In debug we can just pause on the breakpoint and this might be considered as a hang,
                    // that's why in Debug we send events only in unit-tests. Or you may enable it manually to debug.
                    return
                }
#endif
                self.receiver.nonFatalHangReceived(info: info)
            }
        }
        // we update date every time to measure hang when it started
        self.lastMainThreadDate = self.timeProvider.now()
    }

    private var currentHangInterval: DispatchTimeInterval {
        let now = timeProvider.now()
        return lastMainThreadDate.advanced(by: detectionTimerInterval).distance(to: now)
    }

    private func readAndClearHangInfo() -> HangInfo? {
        let result: HangInfo? = storage.readJSON(key: StorageKey.hangInfo)
        didHangPreviouslyValue = result != nil
        clearHangInfo()
        return result
    }

    private func store(hangInfo: HangInfo) {
        hangInfoInMemory = hangInfo
        storage.writeJSON(key: StorageKey.hangInfo, value: hangInfo)
    }

    private func clearHangInfo() {
        hangInfoInMemory = nil
        storage.writeJSON(key: StorageKey.hangInfo, value: nil as HangInfo?)
    }

    deinit {
        // we shouldn't deallocate timer in suspended state
        // https://developer.apple.com/documentation/dispatch/1452801-dispatch_suspend
        if self.isSuspended {
            detectionTimer.resume()
        }
        detectionTimer.cancel()
    }

    func didHangPreviously() -> Bool {
        // We are not sure if this method will be called before or after removing hangInfo from the storage,
        // that is why we cache if hangInfo was nil or not inside `readAndClearHangInfo` too.
        if let didHangPreviouslyValue = didHangPreviouslyValue {
            return didHangPreviouslyValue
        }
        let result = (storage.readJSON(key: StorageKey.hangInfo) as HangInfo? != nil)
        didHangPreviouslyValue = result
        return result
    }
    private var didHangPreviouslyValue: Bool?

    // we store the same hang info in memory too to not request it from disk every second, but only on startup
    private var hangInfoInMemory: HangInfo?

    enum StorageKey: String {
        case hangInfo
    }
}
