//
//  UITestsHelper.swift
//  PerformanceSuite-PerformanceApp
//
//  Created by Gleb Tarasov on 19/12/2023.
//

import Foundation

class UITestsHelper {
    static func prepareForTestsIfNeeded() {
        if shouldClearStorage {
            clearStorage()
        }
    }

    static let isInTests = ProcessInfo.processInfo.environment[inTestsKey] != nil
    private static let shouldClearStorage = ProcessInfo.processInfo.environment[clearStorageKey] != nil

    private static func clearStorage() {
        guard let domain = Bundle.main.bundleIdentifier else {
            fatalError("no bundle identifier")
        }
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.resetStandardUserDefaults()

        // Firebase keeps reports and its previous-crash marker outside defaults.
        // Reset that state before Firebase is configured for a new test; relaunches
        // within a test omit CLEAR_STORAGE and must preserve the real crash marker.
        let fileManager = FileManager.default
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            fatalError("no caches directory")
        }
        let crashlyticsCache = caches.appendingPathComponent("com.crashlytics.data")
            .appendingPathComponent(domain)
        if fileManager.fileExists(atPath: crashlyticsCache.path) {
            do {
                try fileManager.removeItem(at: crashlyticsCache)
            } catch {
                fatalError("Couldn't clear Crashlytics test state: \(error)")
            }
        }
    }
}
