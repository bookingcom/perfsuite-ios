//
//  CrashesInterceptor.swift
//  PerformanceApp
//
//  Created by Gleb Tarasov on 18/12/2023.
//

import Foundation


/// Simple crashes handler. Can intercept crashes and store the flag about that for the next launch.
/// In your app you probably use FirebaseCrashlytics or something like that.
class CrashesInterceptor {
    static func interceptCrashes() {
        UserDefaults.standard.removeObject(forKey: key)

        signal(SIGTRAP) { s in
            debugPrint("Crash intercepted")
            UserDefaults.standard.set(true, forKey: key)
            UserDefaults.standard.synchronize()
            exit(s)
        }
    }

    static func didCrashDuringPreviousLaunch() -> Bool {
        return UserDefaults.standard.bool(forKey: key)
    }
}

private let key = "app_did_crash"
