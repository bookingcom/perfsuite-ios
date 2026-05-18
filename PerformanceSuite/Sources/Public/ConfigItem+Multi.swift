//
//  ConfigItem+Multi.swift
//  PerformanceSuite
//
//  Created by Ahmed Nafei on 01/05/2026.
//

import UIKit

// MARK: - Non-generic receivers (iOS 15+)

extension ConfigItem {

    public static func startupTime(_ receivers: [StartupTimeReceiver]) -> ConfigItem {
        .startupTime(MultiStartupTimeReceiver(receivers: receivers))
    }

    public static func hangs(_ receivers: [HangsReceiver]) -> ConfigItem {
        .hangs(MultiHangsReceiver(receivers: receivers))
    }

    public static func appLevelRendering(_ receivers: [AppRenderingMetricsReceiver]) -> ConfigItem {
        .appLevelRendering(MultiAppRenderingMetricsReceiver(receivers: receivers))
    }

    public static func watchdogTerminations(_ receivers: [WatchdogTerminationsReceiver]) -> ConfigItem {
        .watchdogTerminations(MultiWatchdogTerminationsReceiver(receivers: receivers))
    }

    public static func viewControllerLeaks(
        _ receivers: [ViewControllerLeaksReceiver],
        shouldTrack: ((UIViewController) -> Bool)? = nil
    ) -> ConfigItem {
        .viewControllerLeaks(MultiViewControllerLeaksReceiver(
            receivers: receivers,
            shouldTrack: shouldTrack
        ))
    }
}

// MARK: - Generic receivers (iOS 16+)

@available(iOS 16.0, *)
extension ConfigItem {

    public static func screenLevelTTI<Screen>(
        screenIdentifier: @escaping (UIViewController) -> Screen?,
        receivers: [any TTIMetricsReceiver<Screen>]
    ) -> ConfigItem {
        .screenLevelTTI(MultiTTIMetricsReceiver(
            screenIdentifier: screenIdentifier,
            receivers: receivers))
    }

    public static func screenLevelRendering<Screen>(
        screenIdentifier: @escaping (UIViewController) -> Screen?,
        receivers: [any RenderingMetricsReceiver<Screen>]
    ) -> ConfigItem {
        .screenLevelRendering(MultiRenderingMetricsReceiver(
            screenIdentifier: screenIdentifier,
            receivers: receivers))
    }

    public static func fragmentTTI<Fragment>(
        _ receivers: [any FragmentTTIMetricsReceiver<Fragment>]
    ) -> ConfigItem {
        .fragmentTTI(MultiFragmentTTIMetricsReceiver(receivers: receivers))
    }
}
