//
//  HangsReporter.swift
//  PerformanceTrackingServices#iphonesimulator-x86_64,static
//
//  Created by Gleb Tarasov on 08/09/2021.
//

import Foundation
import UIKit

public protocol HangReceiver: AnyObject {

    /// This method will be called on `PerformanceSuite.consumerQueue` just after the app launch for the fatal hangs,
    /// in case during the previous launch app was terminated during the main thread hang.
    /// - Parameter info: info related to the hang
    func fatalHangReceived(info: HangInfo)

    /// This method will be called on `PerformanceSuite.consumerQueue` after the main thread freeze resolved.
    /// - Parameter info: info related to the hang
    func nonFatalHangReceived(info: HangInfo)
}


/// OOMReporter should know if app was killed because of the hang.
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
    private let appStateProvider: AppStateProvider
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

    private let receiver: HangReceiver

    init(
        timeProvider: TimeProvider = DefaultTimeProvider(),
        storage: Storage = UserDefaults.standard,
        startupProvider: StartupProvider,
        appStateProvider: AppStateProvider = UIApplication.shared,
        workingQueue: DispatchQueue = PerformanceSuite.queue,
        detectionTimerInterval: DispatchTimeInterval = .seconds(1),
        hangThreshold: DispatchTimeInterval = .seconds(2),
        didCrashPreviously: Bool = false,
        enabledInDebug: Bool = false,
        receiver: HangReceiver
    ) {
        self.timeProvider = timeProvider
        self.storage = storage
        self.startupProvider = startupProvider
        self.appStateProvider = appStateProvider
        self.workingQueue = workingQueue
        self.detectionTimerInterval = detectionTimerInterval
        self.hangThreshold = hangThreshold
        self.didCrashPreviously = didCrashPreviously
        self.enabledInDebug = enabledInDebug
        self.receiver = receiver
        self.lastMainThreadDate = timeProvider.now()
        self.detectionTimer = DispatchSource.makeTimerSource(flags: .strict, queue: workingQueue)

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

            self.start()
        }
    }

    private func start() {
        lastMainThreadDate = timeProvider.now()
        DispatchQueue.main.async {
            // we should call `UIApplication.shared.applicationState` on the main thread only
            let inBackground = self.appStateProvider.applicationState == .background
            PerformanceSuite.queue.async {
                self.scheduleDetectionTimer(inBackground: inBackground)
                self.subscribeToApplicationEvents()
            }
        }
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
        PerformanceSuite.consumerQueue.async {
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
            PerformanceSuite.consumerQueue.async {
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
