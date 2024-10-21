//
//  AppStartInfoHolder.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 15/12/2022.
//

import UIKit

/// App can be launched not only by user clicking on the app's icon, but in some other weird circumstances.
///
/// Usually such non-standard app starts can affect different metrics: startup time may very,
/// TTI or rendering may be too long (it will be measured until app really launched by the user) for the first screen of the app,
/// memory terminations, fatal and non-fatal hangs can be reported wrongly (as system may kill your app back in the background).
///
/// So better to ignore events from such abnormal starts or at least report them separately.
public struct AppStartInfo: Equatable, Codable {

    /// Starting from iOS 15 system can pre-warm app by executing it's `main()`,
    /// but without showing the UI.
    ///
    /// You need to call `PerformanceMonitoring.onMainStarted()` to detect prewarming.
    public let appStartedWithPrewarming: Bool

    static func merge(_ lhs: AppStartInfo, _ rhs: AppStartInfo) -> AppStartInfo {
        return AppStartInfo(appStartedWithPrewarming: lhs.appStartedWithPrewarming || rhs.appStartedWithPrewarming)
    }

    static var empty: AppStartInfo {
        return AppStartInfo(appStartedWithPrewarming: false)
    }
}

public struct AppRuntimeInfo: Equatable, Codable {
    public private(set) var openedScreens: [String]

    mutating func append(screen: String) {
        openedScreens.append(screen)
    }

    static var empty: AppRuntimeInfo {
        return AppRuntimeInfo(openedScreens: [])
    }
}

public protocol StartupTimeReceiver: AnyObject {
    func startupTimeReceived(_ data: StartupTimeData)
}

class AppInfoHolder {

    // Example can be found in FirebasePerformance
    // https://github.com/firebase/firebase-ios-sdk/blob/df5d2c6d26fb67a3eb49caad00452710244204f4/FirebasePerformance/Sources/AppActivity/FPRAppActivityTracker.m#L80
    private static let prewarmingFlagEnvironmentName = "ActivePrewarm"
    private static let prewarmingFlagEnvironmentValue = "1"

    private static var appStartInfoStorage = AppStartInfo.empty
    private static var appRuntimeInfoStorage = AppRuntimeInfo.empty

    // We are synchronising access to the `appStartInfoStorage` and `appRuntimeInfoStorage`
    private static let queue = DispatchQueue(label: "performance_suite.AppStartInfoHolder", attributes: .concurrent)

    static var appStartInfo: AppStartInfo {
        return queue.sync {
            return appStartInfoStorage
        }
    }

    /// This function should be called once just in the beginning of `main()` function of the app.
    /// This is not required, but we won't have prewarming information though.
    /// But we still will have `totalTime` there.
    static func recordMainStarted() {
        assert(Thread.isMainThread)

        queue.async(flags: .barrier) {
            // picked the idea from FirebasePerformance
            // we should track it in the beginning of main(), because later this flag will not be available in the environment
            let appStartedWithPrewarming = ProcessInfo.processInfo.environment[prewarmingFlagEnvironmentName] == prewarmingFlagEnvironmentValue
            appStartInfoStorage = AppStartInfo(appStartedWithPrewarming: appStartedWithPrewarming)
        }
    }

    static func screenOpened(_ screen: String) {
        queue.async(flags: .barrier) {
            appRuntimeInfoStorage.append(screen: screen)
        }
    }

    static var appRuntimeInfo: AppRuntimeInfo {
        return queue.sync {
            return appRuntimeInfoStorage
        }
    }

    static func resetForTests() {
        queue.sync(flags: .barrier) {
            appStartInfoStorage = .empty
            appRuntimeInfoStorage = .empty
        }
    }
}
