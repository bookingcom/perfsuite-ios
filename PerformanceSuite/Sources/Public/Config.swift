//
//  Config.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 26/01/2022.
//

import Foundation

public enum ConfigItem {
    case screenLevelTTI(any TTIMetricsReceiver)
    case screenLevelRendering(any RenderingMetricsReceiver)
    case appLevelRendering(AppRenderingMetricsReceiver)
    case startupTime(StartupTimeReceiver)
    case watchdogTerminations(WatchdogTerminationsReceiver)
    case hangs(HangsReceiver)
    case viewControllerLeaks(ViewControllerLeaksReceiver)
    case logging(any ViewControllerLoggingReceiver)
    case fragmentTTI(any FragmentTTIMetricsReceiver)
}

public typealias Config = [ConfigItem]

public typealias PerformanceSuiteMetricsReceiver = TTIMetricsReceiver & RenderingMetricsReceiver & AppRenderingMetricsReceiver
& WatchdogTerminationsReceiver & HangsReceiver & ViewControllerLeaksReceiver & StartupTimeReceiver & ViewControllerLoggingReceiver
& FragmentTTIMetricsReceiver


extension ConfigItem {
    var isRendering: Bool {
        switch self {
        case .appLevelRendering, .screenLevelRendering:
            return true
        default:
            return false
        }
    }
}

extension Config {
    var renderingEnabled: Bool {
        return contains { $0.isRendering }
    }

    private func findReceiver<T>(title: String, extractor: (ConfigItem) -> T?) -> T? {
        var result: T?
        for item in self {
            let receiver = extractor(item)
            if receiver != nil {
                if result != nil {
                    assertionFailure("You passed 2 instances of ConfigItem.\(title). You can pass only 1.")
                }
                result = receiver
            }
        }
        return result
    }

    var screenTTIReceiver: (any TTIMetricsReceiver)? {
        findReceiver(title: "screenLevelTTI") { item in
            if case .screenLevelTTI(let result) = item {
                return result
            } else {
                return nil
            }
        }
    }

    var screenRenderingReceiver: (any RenderingMetricsReceiver)? {
        findReceiver(title: "screenLevelRendering") { item in
            if case .screenLevelRendering(let result) = item {
                return result
            } else {
                return nil
            }
        }
    }

    var appRenderingReceiver: AppRenderingMetricsReceiver? {
        findReceiver(title: "appLevelRendering") { item in
            if case .appLevelRendering(let result) = item {
                return result
            } else {
                return nil
            }
        }
    }

    var watchdogTerminationsReceiver: WatchdogTerminationsReceiver? {
        findReceiver(title: "watchdogTerminations") { item in
            if case .watchdogTerminations(let result) = item {
                return result
            } else {
                return nil
            }
        }
    }

    var hangsReceiver: HangsReceiver? {
        findReceiver(title: "hangs") { item in
            if case .hangs(let result) = item {
                return result
            } else {
                return nil
            }
        }
    }

    var viewControllerLeaksReceiver: ViewControllerLeaksReceiver? {
        findReceiver(title: "viewControllerLeaks") { item in
            if case .viewControllerLeaks(let result) = item {
                return result
            } else {
                return nil
            }
        }
    }

    var startupTimeReceiver: StartupTimeReceiver? {
        findReceiver(title: "startupTime") { item in
            if case .startupTime(let result) = item {
                return result
            } else {
                return nil
            }
        }
    }

    var loggingReceiver: (any ViewControllerLoggingReceiver)? {
        findReceiver(title: "logging") { item in
            if case .logging(let result) = item {
                return result
            } else {
                return nil
            }
        }
    }

    var fragmentTTIReceiver: (any FragmentTTIMetricsReceiver)? {
        findReceiver(title: "fragmentTTI") { item in
            if case .fragmentTTI(let result) = item {
                return result
            } else {
                return nil
            }
        }
    }

    public static func all(receiver: any PerformanceSuiteMetricsReceiver) -> Self {
        [
            .screenLevelTTI(receiver),
            .screenLevelRendering(receiver),
            .appLevelRendering(receiver),
            .startupTime(receiver),
            .watchdogTerminations(receiver),
            .hangs(receiver),
            .viewControllerLeaks(receiver),
            .logging(receiver),
            .fragmentTTI(receiver),
        ]
    }
}
