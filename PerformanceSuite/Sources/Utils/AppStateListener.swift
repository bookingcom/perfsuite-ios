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

    /// Called synchronously on main before `isInBackground` changes, so work done here finishes within the
    /// `willResignActive` / `didBecomeActive` notification turn. Not called when the state doesn't change, e.g. on
    /// the first `didBecomeActive` after launch. `didChange` follows asynchronously.
    var willChange: () -> Void { get set }
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
    }

    public var didChange: () -> Void = {}

    public var willChange: () -> Void {
        get {
            lock.lock()
            defer { lock.unlock() }
            return willChangeStorage
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            willChangeStorage = newValue
        }
    }

    @objc private func appWillResignActive() {
        if !isInBackground {
            willChange()
        }
        lock.lock()
        wasInBackgroundStorage = true
        isInBackgroundStorage = true
        lock.unlock()

        PerformanceMonitoring.queue.async {
            self.didChange()
        }
    }

    @objc private func appDidBecomeActive() {
        if isInBackground {
            willChange()
        }
        self.lock.lock()
        self.isInBackgroundStorage = false
        self.lock.unlock()

        PerformanceMonitoring.queue.async {
            self.didChange()
        }
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
    private var willChangeStorage: () -> Void = {}
    private let lock = NSLock()
}
