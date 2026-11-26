//
//  LoggingObserver.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 23/09/2022.
//

import Foundation
import UIKit
import SwiftUI

/// Use this protocol for light-weight operations like logging only,
/// it is not intended to be used for some business-logic.
///
/// If you execute something heavy, offload it to some other background thread.
public protocol ViewControllerLoggingReceiver<ScreenIdentifier>: ScreenMetricsReceiver {

    /// Method is called during view controller's initialization
    func onInit(screen: ScreenIdentifier)

    /// Method is called during view controller's `viewDidLoad`
    func onViewDidLoad(screen: ScreenIdentifier)

    /// Method is called during view controller's `viewWillAppear`
    func onViewWillAppear(screen: ScreenIdentifier)

    /// Method is called during view controller's `viewDidAppear`
    func onViewDidAppear(screen: ScreenIdentifier)

    /// Method is called during view controller's `viewWillDisappear`
    func onViewWillDisappear(screen: ScreenIdentifier)
}


/// Observer which forward all delegate methods to its receiver for logging purposes
final class LoggingObserver<V: ViewControllerLoggingReceiver>: ViewControllerInstanceObserver {

    init(screen: V.ScreenIdentifier, receiver: V) {
        self.screen = screen
        self.receiver = receiver
    }

    private let screen: V.ScreenIdentifier
    private let receiver: V

    // releaseViewControllersOnMain: keep on cleanup.
    /// Set once on `PerformanceMonitoring.queue`, before this observer queues anything, and read on `consumerQueue`.
    private weak var viewController: UIViewController?

    // releaseViewControllersOnMain: keep on cleanup.
    func didCreate(for viewController: UIViewController) {
        self.viewController = viewController
    }

    // releaseViewControllersOnMain: keep on cleanup.
    /// Calls the receiver on `consumerQueue` so that it can never release the view controller last.
    ///
    /// A receiver may load the view controller from its screen identifier and drop it last on `consumerQueue`. UIKit
    /// then marks it as deallocating off main but runs `dealloc` later on main; if its view leaves the window in
    /// between, `viewDidMoveToWindow:shouldAppearOrDisappear:` forms a weak reference to it and the app aborts.
    /// So while the receiver runs this observer holds one extra retain, released on main after the receiver returns.
    /// While the block waits on the queue the view controller is held weakly: queue backlogs do not delay its
    /// deallocation. If it is already gone or deallocating when the block runs, the receiver is called as before.
    /// The receiver runs in its own autorelease pool, so whatever it autoreleases is dropped before our release is queued.
    private func asyncCallingReceiver(_ call: @escaping (V, V.ScreenIdentifier) -> Void) {
        PerformanceMonitoring.consumerQueue.async {
            let reference = self.retainViewController()
            autoreleasepool {
                call(self.receiver, self.screen)
            }
            if let reference {
                DispatchQueue.main.async {
                    reference.release()
                }
            }
        }
    }

    // releaseViewControllersOnMain: keep on cleanup.
    /// Returns the only reference this observer keeps: the strong local from the weak load ends with this call.
    /// `@inline(never)` keeps that boundary: inlined, the strong local could live past `DispatchQueue.main.async`
    /// and be released on `consumerQueue` after main has released the returned reference.
    @inline(never)
    private func retainViewController() -> Unmanaged<UIViewController>? {
        guard let viewController else {
            return nil
        }
        return Unmanaged.passRetained(viewController)
    }

    func beforeInit() {
        if PerformanceMonitoring.experiments.releaseViewControllersOnMain {
            // releaseViewControllersOnMain: variant implementation; keep on cleanup.
            asyncCallingReceiver { $0.onInit(screen: $1) }
        } else {
            // releaseViewControllersOnMain: base implementation; remove on cleanup.
            PerformanceMonitoring.consumerQueue.async {
                self.receiver.onInit(screen: self.screen)
            }
        }
    }

    func beforeViewDidLoad() {
        if PerformanceMonitoring.experiments.releaseViewControllersOnMain {
            // releaseViewControllersOnMain: variant implementation; keep on cleanup.
            asyncCallingReceiver { $0.onViewDidLoad(screen: $1) }
        } else {
            // releaseViewControllersOnMain: base implementation; remove on cleanup.
            PerformanceMonitoring.consumerQueue.async {
                self.receiver.onViewDidLoad(screen: self.screen)
            }
        }
    }

    func afterViewWillAppear() {
        if PerformanceMonitoring.experiments.releaseViewControllersOnMain {
            // releaseViewControllersOnMain: variant implementation; keep on cleanup.
            asyncCallingReceiver { $0.onViewWillAppear(screen: $1) }
        } else {
            // releaseViewControllersOnMain: base implementation; remove on cleanup.
            PerformanceMonitoring.consumerQueue.async {
                self.receiver.onViewWillAppear(screen: self.screen)
            }
        }
    }

    func afterViewDidAppear() {
        if PerformanceMonitoring.experiments.releaseViewControllersOnMain {
            // releaseViewControllersOnMain: variant implementation; keep on cleanup.
            asyncCallingReceiver { $0.onViewDidAppear(screen: $1) }
        } else {
            // releaseViewControllersOnMain: base implementation; remove on cleanup.
            PerformanceMonitoring.consumerQueue.async {
                self.receiver.onViewDidAppear(screen: self.screen)
            }
        }
    }

    func beforeViewWillDisappear() {
        if PerformanceMonitoring.experiments.releaseViewControllersOnMain {
            // releaseViewControllersOnMain: variant implementation; keep on cleanup.
            asyncCallingReceiver { $0.onViewWillDisappear(screen: $1) }
        } else {
            // releaseViewControllersOnMain: base implementation; remove on cleanup.
            PerformanceMonitoring.consumerQueue.async {
                self.receiver.onViewWillDisappear(screen: self.screen)
            }
        }
    }

    static var identifier: AnyObject {
        return loggingObserverIdentifier
    }
}

private let loggingObserverIdentifier = NSObject()
