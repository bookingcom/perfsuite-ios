//
//  OutOfMemoryReporter.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 25/01/2022.
//

import Foundation
import UIKit

public struct OOMData {

    /// Application state during OOM.
    /// The most important OOM that we should fix are when `applicationState == .active`.
    /// In this case crash is visible to the user.
    ///
    /// JFYI: some other background terminations are tracked as background OOM, because it is hard to differ such events.
    /// For example, fatal hang in background is detected as a background OOM.
    /// Also, iOS can kill our app, because it uses too much CPU in background,
    /// and this event will also be reported as a background OOM, etc.
    public let applicationState: UIApplication.State?

    /// Number of memory warnings generated before OOM
    public let memoryWarnings: Int?
}


/// Object can receive events about OOM from `OutOfMemoryReporter`.
public protocol OutOfMemoryReceiver: AnyObject {

    /// This method will be called on `PerformanceSuite.consumerQueue` just after the app launch,
    /// in case during the previous launch app was killed by the system because of the memory warning
    /// (or because any other reason that we are not aware about).
    func outOfMemoryTerminationReceived(_ data: OOMData)
}

/// Object detects if the previous death of the application is related to OOM.
/// Initial idea is taken from here: https://engineering.fb.com/2015/08/24/ios/reducing-fooms-in-the-facebook-ios-app/
final class OutOfMemoryReporter: AppMetricsReporter {

    private struct AppInformation {
        var bundleVersion: String?
        var systemVersion: String?
        var preferredLanguages: [String]?
        var preferredLocalizations: [String]?
        var memoryWarnings: Int?
        var systemRebootTime: Date?
        var appState: UIApplication.State?
        var appTerminated: Bool?
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
    }

    init(
        storage: Storage, didCrashPreviously: Bool = false, didHangPreviouslyProvider: DidHangPreviouslyProvider? = nil,
        enabledInDebug: Bool = false, receiver: OutOfMemoryReceiver
    ) {
        self.storage = storage
        self.didCrashPreviously = didCrashPreviously
        self.didHangPreviouslyProvider = didHangPreviouslyProvider
        self.enabledInDebug = enabledInDebug
        self.receiver = receiver

        subscribeToNotifications()
        detectPreviousTermination()
    }


    private let storage: Storage
    private let didCrashPreviously: Bool
    private let didHangPreviouslyProvider: DidHangPreviouslyProvider?
    private let enabledInDebug: Bool
    private let receiver: OutOfMemoryReceiver

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
        PerformanceSuite.queue.async {
            var warnings: Int = self.storage.read(key: StorageKey.memoryWarnings) ?? 0
            warnings += 1
            self.storage.write(key: StorageKey.memoryWarnings, value: warnings)
        }
    }

    @objc private func appWillTerminate() {
        // We use sync here, because otherwise app may be terminated before we saved the value
        PerformanceSuite.queue.sync {
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
        PerformanceSuite.queue.async {
            self.storage.write(key: StorageKey.appState, value: state.rawValue)
        }
    }

    private func detectPreviousTermination() {
        DispatchQueue.main.async {
            let applicationState = UIApplication.shared.applicationState
            PerformanceSuite.queue.async {
                let storedAppInformation = self.readStoredAppInformation()
                let actualAppInformation = self.generateActualAppInformation(applicationState: applicationState)
                self.detectTermination(storedAppInformation: storedAppInformation, actualAppInformation: actualAppInformation)
                self.storeAppInformation(actualAppInformation)
            }
        }
    }

    private func detectTermination(storedAppInformation: AppInformation, actualAppInformation: AppInformation) {
        if storedAppInformation.bundleVersion == nil {
            // the first launch of the app, ignore
        } else if didCrashPreviously {
            // it was the real crash, not OOM, ignore
        } else if storedAppInformation.appTerminated == true {
            // app was terminated by the user, ignore
        } else if storedAppInformation.preferredLanguages != actualAppInformation.preferredLanguages
            || storedAppInformation.preferredLocalizations != actualAppInformation.preferredLocalizations
        {
            // system or app language changed, app is killed by the system after that, ignore
        } else if storedAppInformation.systemVersion != actualAppInformation.systemVersion {
            // system was updated, app might be killed because of that
        } else if storedAppInformation.bundleVersion != actualAppInformation.bundleVersion {
            // app was updated and killed by the system, ignore
        } else if (actualAppInformation.systemRebootTime?.timeIntervalSinceReferenceDate ?? 0)
            - (storedAppInformation.systemRebootTime?.timeIntervalSinceReferenceDate ?? 0)
            > systemUptimeChangeThreshold
        {
            // device was rebooted between 2 launches of the app, this may cause the termination, ignore
        } else if didHangPreviouslyProvider?.didHangPreviously() == true {
            // system killed the app because of the hang on the main thread, this wasn't OOM, ignore
        } else {
            // we don't know any more valid reason, consider this as OOM
            let data = OOMData(
                applicationState: storedAppInformation.appState,
                memoryWarnings: storedAppInformation.memoryWarnings)
            PerformanceSuite.consumerQueue.async {
                #if DEBUG
                    if !self.enabledInDebug {
                        // In debug app might be just killed from the Xcode during the debug session
                        // So in DEBUG we send events only in unit-tests
                        return
                    }
                #endif
                self.receiver.outOfMemoryTerminationReceived(data)
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
            appTerminated: storage.read(key: StorageKey.appTerminated)
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
            appTerminated: false
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
