//
//  AppStateListener.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 12/07/2021.
//

import UIKit

public protocol AppStateListener: AnyObject {
    var wasInBackground: Bool { get }
    var isInBackground: Bool { get }

    var didChange: () -> Void { get set }

    /// Called synchronously on main on `willResignActive` and `willTerminate`, so work done here finishes within
    /// that notification turn.
    var willResignActive: () -> Void { get set }
}

public final class DefaultAppStateListener: AppStateListener {

    public init() {
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil)
    }

    public var didChange: () -> Void = {}

    public var willResignActive: () -> Void {
        get {
            lock.lock()
            defer { lock.unlock() }
            return willResignActiveStorage
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            willResignActiveStorage = newValue
        }
    }

    @objc private func appWillResignActive() {
        lock.lock()
        wasInBackgroundStorage = true
        isInBackgroundStorage = true
        lock.unlock()
        willResignActive()

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

    @objc private func appWillTerminate() {
        willResignActive()
    }

    public var wasInBackground: Bool {
        lock.lock()
        let result = wasInBackgroundStorage
        lock.unlock()
        return result
    }

    public var isInBackground: Bool {
        lock.lock()
        let result = isInBackgroundStorage
        lock.unlock()
        return result
    }

    private var isInBackgroundStorage = false
    private var wasInBackgroundStorage = false
    private var willResignActiveStorage: () -> Void = {}
    private let lock = NSLock()
}
