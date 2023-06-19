//
//  HangInfo.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 13/09/2022.
//

import Foundation
import MachO
import UIKit

/// Structure contains call stack text and all the info which is needed to symbolicate this stack.
public struct HangInfo: Codable {

    /// Actual text of the stack trace
    public let callStack: String

    /// CPU Architecture (arm64, arm64e). Is needed to symbolicate stack traces.
    public let architecture: String

    /// iOS version (13.1, 15.0.1, ...). Is needed to symbolicate stack traces.
    public let iOSVersion: String

    /// Information about how app was started.
    /// You may want to ignore hang events events if app started after pre-warming or in background. Because the detection is not reliable in that case.
    public let appStartInfo: AppStartInfo


    /// Information about app runtime
    public let appRuntimeInfo: AppRuntimeInfo

    /// Flag that hang happened during startup (before viewDidAppear of the first view controller).
    /// You may want to ignore startup non-fatal hangs, because those events are measured with startup time.
    public let duringStartup: Bool

    /// Store milliseconds to make it Codable
    private var durationInMilliseconds: Int

    /// Approximate duration of the hang
    public internal(set) var duration: DispatchTimeInterval {
        get {
            return .milliseconds(durationInMilliseconds)
        }
        set {
            durationInMilliseconds = newValue.milliseconds ?? 0
        }
    }

    init(
        callStack: String,
        architecture: String,
        iOSVersion: String,
        appStartInfo: AppStartInfo,
        appRuntimeInfo: AppRuntimeInfo,
        duringStartup: Bool,
        duration: DispatchTimeInterval
    ) {
        self.callStack = callStack
        self.architecture = architecture
        self.iOSVersion = iOSVersion
        self.appStartInfo = appStartInfo
        self.appRuntimeInfo = appRuntimeInfo
        self.duringStartup = duringStartup
        self.durationInMilliseconds = duration.milliseconds ?? 0
    }

    public static func with(callStack: String, duringStartup: Bool, duration: DispatchTimeInterval) -> HangInfo {
        return HangInfo(
            callStack: callStack,
            architecture: currentArchitecture,
            iOSVersion: currentIOSVersion,
            appStartInfo: AppInfoHolder.appStartInfo,
            appRuntimeInfo: AppInfoHolder.appRuntimeInfo,
            duringStartup: duringStartup,
            duration: duration)
    }

    private static var currentArchitecture: String {
        let info = NXGetLocalArchInfo()
        if let name = info?.pointee.name {
            return String(cString: name)
        } else {
            return unknownKeyword
        }
    }

    private static var currentIOSVersion: String {
        return UIDevice.current.systemVersion
    }
}
