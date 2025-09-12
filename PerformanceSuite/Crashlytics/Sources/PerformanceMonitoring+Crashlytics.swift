//
//  PerformanceMonitoring+Crashlytics.swift
//  Pods
//
//  Created by Gleb Tarasov on 09/09/2024.
//

import FirebaseCore
import FirebaseCrashlytics

// In SwiftPM we have separate targets
#if canImport(PerformanceSuiteCrashlytics)
import PerformanceSuite
#endif

extension PerformanceMonitoring {
    /// Method to start PerformanceSuite with Crashlytics Support.
    /// Additionally to `enable` method it:
    ///    - takes `didCrashPreviously` from Crashlytics
    ///    - adds `CrashlyticsHangsReceiverWrapper` to send hangs to Crashlytics
    /// - Parameters:
    ///   - config: By passing config you are enabling or disabling some parts of the PerformanceSuite
    ///   - hangsReportingMode: Defines which hangs and how we send to Crashlytics
    ///   - storage: Simple key/value storage which we use to store some simple objects, by default `UserDefaults` is used.
    ///   - experiments: Feature flags that can be used to enable/disable some experimentation features inside PerformanceSuite. Is used for A/B testing in production.
    ///   - crashlyticsEnabledInDebug: If `false`, we won't report anything to Crashlytics if `DEBUG` is true.
    ///   **NB:** *Make sure that `FirebaseApp.configure() is called before calling this method! App will crash otherwise.*`
    public static func enableWithCrashlyticsSupport(
        config: Config = [],
        settings: CrashlyticsHangsSettings,
        storage: Storage = UserDefaults.standard,
        experiments: Experiments = Experiments(),
        crashlyticsEnabledInDebug: Bool = true,
    ) throws {
        #if DEBUG
        let crashlyticsEnabled = crashlyticsEnabledInDebug
        #else
        let crashlyticsEnabled = true
        #endif

        if crashlyticsEnabled {
            guard FirebaseApp.allApps?.count ?? 0 > 0 else {
                fatalError("Firebase is not configured yet. Please call `FirebaseApp.configure()` before calling this method.")
            }

            let didCrashPreviously = Crashlytics.crashlytics().didCrashDuringPreviousExecution()
            let wrappedConfig = config.map { c in
                switch c {
                case .hangs(let receiver):
                    // wrap hang receiver with Crashlytics wrapper to send hangs to Crashlytics
                    return ConfigItem.hangs(CrashlyticsHangsReceiverWrapper(hangsReceiver: receiver, settings: settings))
                default:
                    return c
                }
            }

            try PerformanceMonitoring.enable(config: wrappedConfig, storage: storage, didCrashPreviously: didCrashPreviously, experiments: experiments)
        } else {
            try PerformanceMonitoring.enable(config: config, storage: storage, didCrashPreviously: false, experiments: experiments)
        }
    }
}
