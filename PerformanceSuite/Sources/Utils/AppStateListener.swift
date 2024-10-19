//
//  AppStateListener.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 12/07/2021.
//

import UIKit

protocol AppStateListener: AnyObject {
    var wasInBackground: Bool { get }
    var isInBackground: Bool { get }

    var didChange: () -> Void { get set }
}

class DefaultAppStateListener: AppStateListener {

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil)

    }

    var didChange: () -> Void = {}

    @objc private func appWillResignActive() {
        lock.lock()
        wasInBackgroundStorage = true
        isInBackgroundStorage = true
        lock.unlock()

        PerformanceMonitoring.queue.async {
            self.didChange()
        }
    }

    @objc private func appDidBecomeActive() {
        self.lock.lock()
        self.isInBackgroundStorage = false
        self.lock.unlock()

        PerformanceMonitoring.queue.async {
            self.didChange()
        }
    }

    var wasInBackground: Bool {
        lock.lock()
        let result = wasInBackgroundStorage
        lock.unlock()
        return result
    }

    var isInBackground: Bool {
        lock.lock()
        let result = isInBackgroundStorage
        lock.unlock()
        return result
    }

    private var isInBackgroundStorage = false
    private var wasInBackgroundStorage = false
    private let lock = NSLock()
}
