//
//  WatchdogTerminationReporter.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 25/01/2022.
//

import Foundation
import UIKit

public struct WatchdogTerminationData {

    /// Application state during a termination.
    /// The most important terminations that we should fix are when `applicationState == .active`.
    /// In this case it is visible to the user.
    ///
    /// JFYI: some other background terminations are tracked as background watchdog terminations, because it is hard to differ such events.
    /// For example, fatal hang in background is detected as a background watchdog termination.
    public let applicationState: UIApplication.State?

    /// Information about how app was started.
    /// You may want to ignore startup watchdog terminations if app started after pre-warming.
    public let appStartInfo: AppStartInfo?

    /// Flag that termination happened during startup (before viewDidAppear of the first view controller).
    /// You may want to ignore startup watchdog terminations after the pre-warming.
    public let duringStartup: Bool?

    /// Number of memory warnings generated before termination. Can be useful to differ memory terminations from other types.
    public let memoryWarnings: Int?
}


/// Object can receive events about watchdog terminations from `WatchdogTerminationReporter`.
///
/// It detects if the reason of the previous death of the application is unknown.
/// We consider such terminations as Watchdog terminations.
///
/// The reason of a termination can vary: out of memory, too high CPU, something else.
/// But in most cases foreground terminations happen because of some problem in the code.
public protocol WatchdogTerminationsReceiver: AnyObject {

    /// This method will be called on `PerformanceMonitoring.consumerQueue` just after the app launch,
    /// in case during the previous launch app was killed by the system because of the out-of-memory, too high CPU
    /// (or because any other reason that we are not aware about).
    func watchdogTerminationReceived(_ data: WatchdogTerminationData)
}

/// Object detects if the reason of the previous death of the application is unknown.
/// We consider such terminations as Watchdog terminations.
/// Initial idea is taken from here: https://engineering.fb.com/2015/08/24/ios/reducing-fooms-in-the-facebook-ios-app/
final class WatchdogTerminationReporter: AppMetricsReporter {

    private struct AppInformation {
        var bundleVersion: String?
        var systemVersion: String?
        var preferredLanguages: [String]?
        var preferredLocalizations: [String]?
        var memoryWarnings: Int?
        var systemRebootTime: Date?
        var appState: UIApplication.State?
        var appTerminated: Bool?
        var appStartInfo: AppStartInfo?
        var duringStartup: Bool?
    }

    enum StorageKey: String {
        case bundleVersion
        case systemVersion
        case preferredLanguages
        case preferredLocalizations
        case memoryWarnings
        case systemRebootTime
        case appState
        case appTerminated
        case appStartInfo
        case duringStartup
    }

    init(
        storage: Storage, didCrashPreviously: Bool = false,
        didHangPreviouslyProvider: DidHangPreviouslyProvider? = nil,
        startupProvider: StartupProvider,
        appStateProvider: AppStateProvider = UIApplication.shared,
        enabledInDebug: Bool = false,
        receiver: WatchdogTerminationsReceiver
    ) {
        self.storage = storage
        self.didCrashPreviously = didCrashPreviously
        self.didHangPreviouslyProvider = didHangPreviouslyProvider
        self.startupProvider = startupProvider
        self.enabledInDebug = enabledInDebug
        self.receiver = receiver

        PerformanceMonitoring.queue.async {
            startupProvider.notifyAfterAppStarted { [weak self] in
                self?.appStarted()
            }
        }

        let appState = Thread.isMainThread ? appStateProvider.applicationState : DispatchQueue.main.sync { appStateProvider.applicationState }
        detectPreviousTermination(applicationState: appState)
        subscribeToNotifications()
    }


    private let storage: Storage
    private let didCrashPreviously: Bool
    private let didHangPreviouslyProvider: DidHangPreviouslyProvider?
    private let startupProvider: StartupProvider
    private let enabledInDebug: Bool
    private let receiver: WatchdogTerminationsReceiver

    // MARK: - Notifications

    private func subscribeToNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(willResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(willEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil)
    }

    @objc private func appDidReceiveMemoryWarning() {
        PerformanceMonitoring.queue.async {
            var warnings: Int = self.storage.read(key: StorageKey.memoryWarnings) ?? 0
            warnings += 1
            self.storage.write(key: StorageKey.memoryWarnings, value: warnings)
        }
    }

    @objc private func appWillTerminate() {
        // We use sync here, because otherwise app may be terminated before we saved the value
        PerformanceMonitoring.queue.sync {
            self.storage.write(key: StorageKey.appTerminated, value: true)
        }
    }

    @objc private func willResignActive() {
        appChangedState(.inactive)
    }

    @objc private func didBecomeActive() {
        appChangedState(.active)
    }

    @objc private func didEnterBackground() {
        appChangedState(.background)
    }

    @objc private func willEnterForeground() {
        appChangedState(.inactive)
    }

    private func appChangedState(_ state: UIApplication.State) {
        PerformanceMonitoring.queue.async {
            self.storage.write(key: StorageKey.appState, value: state.rawValue)
        }
    }

    private func appStarted() {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        self.storage.write(key: StorageKey.duringStartup, value: false)
    }

    private func detectPreviousTermination(applicationState: UIApplication.State) {
        PerformanceMonitoring.queue.async {
            let storedAppInformation = self.readStoredAppInformation()
            let actualAppInformation = self.generateActualAppInformation(applicationState: applicationState)
            self.detectTermination(storedAppInformation: storedAppInformation, actualAppInformation: actualAppInformation)
            self.storeAppInformation(actualAppInformation)
        }
    }

    private func detectTermination(storedAppInformation: AppInformation, actualAppInformation: AppInformation) {
        if storedAppInformation.bundleVersion == nil {
            // the first launch of the app, ignore
        } else if didCrashPreviously {
            // it was the real crash with a stack trace, ignore
        } else if storedAppInformation.appTerminated == true {
            // app was terminated by the user, ignore
        } else if storedAppInformation.preferredLanguages != actualAppInformation.preferredLanguages
            || storedAppInformation.preferredLocalizations != actualAppInformation.preferredLocalizations {
            // system or app language changed, app is killed by the system after that, ignore
        } else if storedAppInformation.systemVersion != actualAppInformation.systemVersion {
            // system was updated, app might be killed because of that
        } else if storedAppInformation.bundleVersion != actualAppInformation.bundleVersion {
            // app was updated and killed by the system, ignore
        } else if (actualAppInformation.systemRebootTime?.timeIntervalSinceReferenceDate ?? 0)
            - (storedAppInformation.systemRebootTime?.timeIntervalSinceReferenceDate ?? 0)
            > systemUptimeChangeThreshold {
            // device was rebooted between 2 launches of the app, this may cause the termination, ignore
        } else if didHangPreviouslyProvider?.didHangPreviously() == true {
            // system killed the app because of the hang on the main thread, ignore
        } else {
            // we don't know any more valid reason, consider this as a watchdog termination
            let data = WatchdogTerminationData(
                applicationState: storedAppInformation.appState,
                appStartInfo: storedAppInformation.appStartInfo,
                duringStartup: storedAppInformation.duringStartup,
                memoryWarnings: storedAppInformation.memoryWarnings
            )
            PerformanceMonitoring.consumerQueue.async {
                #if DEBUG
                    if !self.enabledInDebug {
                        // In debug app might be just killed from the Xcode during the debug session
                        // So in DEBUG we send events only in unit-tests
                        return
                    }
                #endif
                self.receiver.watchdogTerminationReceived(data)
            }
        }
    }

    private func readStoredAppInformation() -> AppInformation {
        return AppInformation(
            bundleVersion: storage.read(key: StorageKey.bundleVersion),
            systemVersion: storage.read(key: StorageKey.systemVersion),
            preferredLanguages: array(storage.read(key: StorageKey.preferredLanguages)),
            preferredLocalizations: array(storage.read(key: StorageKey.preferredLocalizations)),
            memoryWarnings: storage.read(key: StorageKey.memoryWarnings),
            systemRebootTime: date(storage.read(key: StorageKey.systemRebootTime)),
            appState: appState(storage.read(key: StorageKey.appState)),
            appTerminated: storage.read(key: StorageKey.appTerminated),
            appStartInfo: storage.readJSON(key: StorageKey.appStartInfo),
            duringStartup: storage.read(key: StorageKey.duringStartup)
        )
    }

    private func generateActualAppInformation(applicationState: UIApplication.State) -> AppInformation {
        return AppInformation(
            bundleVersion: Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String,
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            preferredLanguages: Locale.preferredLanguages,
            preferredLocalizations: Bundle.main.preferredLocalizations,
            memoryWarnings: 0,
            systemRebootTime: Date(timeIntervalSinceNow: -ProcessInfo.processInfo.systemUptime),
            appState: applicationState,
            appTerminated: false,
            appStartInfo: AppInfoHolder.appStartInfo,
            duringStartup: startupProvider.appIsStarting
        )
    }

    private func storeAppInformation(_ appInformation: AppInformation) {
        storage.write(key: StorageKey.bundleVersion, value: appInformation.bundleVersion)
        storage.write(key: StorageKey.systemVersion, value: appInformation.systemVersion)
        storage.write(key: StorageKey.preferredLanguages, value: string(appInformation.preferredLanguages))
        storage.write(key: StorageKey.preferredLocalizations, value: string(appInformation.preferredLocalizations))
        storage.write(key: StorageKey.memoryWarnings, value: appInformation.memoryWarnings)
        storage.write(key: StorageKey.systemRebootTime, value: timeInterval(appInformation.systemRebootTime))
        storage.write(key: StorageKey.appState, value: appInformation.appState?.rawValue)
        storage.write(key: StorageKey.appTerminated, value: appInformation.appTerminated)
        storage.writeJSON(key: StorageKey.appStartInfo, value: appInformation.appStartInfo)
        storage.write(key: StorageKey.duringStartup, value: appInformation.duringStartup)
    }

    private func date(_ timeInterval: TimeInterval?) -> Date? {
        guard let timeInterval = timeInterval else {
            return nil
        }
        return Date(timeIntervalSinceReferenceDate: timeInterval)
    }

    private func timeInterval(_ date: Date?) -> TimeInterval? {
        return date?.timeIntervalSinceReferenceDate
    }

    private func array(_ str: String?) -> [String]? {
        guard let str = str else {
            return nil
        }
        return str.components(separatedBy: arraySeparator)
    }

    private func string(_ array: [String]?) -> String? {
        return array?.joined(separator: arraySeparator)
    }

    private func appState(_ value: Int?) -> UIApplication.State? {
        guard let value = value else {
            return nil
        }
        return UIApplication.State(rawValue: value)
    }

    private let arraySeparator = ","
    private let systemUptimeChangeThreshold: TimeInterval = 1
}
