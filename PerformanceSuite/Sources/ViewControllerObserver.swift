//
//  ViewControllerObserver.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 06/07/2021.
//

import ObjectiveC.runtime
import UIKit

/// Observer for UIViewController events
///
/// We use this protocol to observe performance metrics on UIViewController level
protocol ViewControllerObserver {
    func beforeInit(viewController: UIViewController)
    func beforeViewDidLoad(viewController: UIViewController)
    func afterViewWillAppear(viewController: UIViewController)
    func afterViewDidAppear(viewController: UIViewController)
    func beforeViewWillDisappear(viewController: UIViewController)
    func beforeViewDidDisappear(viewController: UIViewController)

    static var identifier: AnyObject { get }
}


/// Observer which creates separate `ViewControllerObserver` for every view controller
final class ViewControllerObserverFactory<T: ViewControllerObserver, S: ScreenMetricsReceiver>: ViewControllerObserver {

    required init(metricsReceiver: S, observerMaker: @escaping (S.ScreenIdentifier) -> T) {
        self.metricsReceiver = metricsReceiver
        self.observerMaker = observerMaker
    }
    private let metricsReceiver: S
    private let observerMaker: (S.ScreenIdentifier) -> T

    private func observer(for viewController: UIViewController) -> T? {
        if PerformanceMonitoring.experiments.observersOnBackgroundQueue {
            dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        } else {
            precondition(Thread.isMainThread)
        }

        if PerformanceMonitoring.experiments.observersOnBackgroundQueue {
            if let observer = ViewControllerObserverFactoryHelper.existingObserver(for: viewController, identifier: T.identifier) as? T {
                return observer
            }
        }

        guard let screen = metricsReceiver.screenIdentifier(for: viewController) else {
            return nil
        }

        if !PerformanceMonitoring.experiments.observersOnBackgroundQueue {
            if let observer = ViewControllerObserverFactoryHelper.existingObserver(for: viewController, identifier: T.identifier) as? T {
                return observer
            }
        }

        let tPointer = unsafeBitCast(T.identifier, to: UnsafeRawPointer.self)
        let observer = observerMaker(screen)
        objc_setAssociatedObject(viewController, tPointer, observer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return observer
    }

    func beforeInit(viewController: UIViewController) {
        if PerformanceMonitoring.experiments.observersOnBackgroundQueue {
            PerformanceMonitoring.queue.async {
                self.observer(for: viewController)?.beforeInit(viewController: viewController)
            }
        } else {
            observer(for: viewController)?.beforeInit(viewController: viewController)
        }
    }

    func beforeViewDidLoad(viewController: UIViewController) {
        if PerformanceMonitoring.experiments.observersOnBackgroundQueue {
            PerformanceMonitoring.queue.async {
                self.observer(for: viewController)?.beforeViewDidLoad(viewController: viewController)
            }
        } else {
            observer(for: viewController)?.beforeViewDidLoad(viewController: viewController)
        }
    }

    func afterViewDidAppear(viewController: UIViewController) {
        if PerformanceMonitoring.experiments.observersOnBackgroundQueue {
            PerformanceMonitoring.queue.async {
                self.observer(for: viewController)?.afterViewDidAppear(viewController: viewController)
            }
        } else {
            observer(for: viewController)?.afterViewDidAppear(viewController: viewController)
        }
    }

    func beforeViewWillDisappear(viewController: UIViewController) {
        if PerformanceMonitoring.experiments.observersOnBackgroundQueue {
            PerformanceMonitoring.queue.async {
                self.observer(for: viewController)?.beforeViewWillDisappear(viewController: viewController)
            }
        } else {
            observer(for: viewController)?.beforeViewWillDisappear(viewController: viewController)
        }
    }

    func afterViewWillAppear(viewController: UIViewController) {
        if PerformanceMonitoring.experiments.observersOnBackgroundQueue {
            PerformanceMonitoring.queue.async {
                self.observer(for: viewController)?.afterViewWillAppear(viewController: viewController)
            }
        } else {
            observer(for: viewController)?.afterViewWillAppear(viewController: viewController)
        }
    }

    func beforeViewDidDisappear(viewController: UIViewController) {
        if PerformanceMonitoring.experiments.observersOnBackgroundQueue {
            PerformanceMonitoring.queue.async {
                self.observer(for: viewController)?.beforeViewDidDisappear(viewController: viewController)
            }
        } else {
            observer(for: viewController)?.beforeViewDidDisappear(viewController: viewController)
        }
    }

    static var identifier: AnyObject {
        return viewControllerObserverFactoryIdentifier
    }
}

private let viewControllerObserverFactoryIdentifier = NSObject()


/// Observer that can hold collection of other observers
class ViewControllerObserverCollection: ViewControllerObserver {

    init(observers: [ViewControllerObserver]) {
        self.observers = observers
    }

    private let observers: [ViewControllerObserver]

    func beforeInit(viewController: UIViewController) {
        observers.forEach { o in
            o.beforeInit(viewController: viewController)
        }
    }

    func beforeViewDidLoad(viewController: UIViewController) {
        observers.forEach { o in
            o.beforeViewDidLoad(viewController: viewController)
        }
    }

    func afterViewDidAppear(viewController: UIViewController) {
        observers.forEach { o in
            o.afterViewDidAppear(viewController: viewController)
        }
    }

    func afterViewWillAppear(viewController: UIViewController) {
        observers.forEach { o in
            o.afterViewWillAppear(viewController: viewController)
        }
    }

    func beforeViewWillDisappear(viewController: UIViewController) {
        observers.forEach { o in
            o.beforeViewWillDisappear(viewController: viewController)
        }
    }

    func beforeViewDidDisappear(viewController: UIViewController) {
        observers.forEach { o in
            o.beforeViewDidDisappear(viewController: viewController)
        }
    }

    static let identifier: AnyObject = NSObject()
}


/// Non-generic helper for generic `ViewControllerObserverFactory`. To put all the static methods and vars there.
final class ViewControllerObserverFactoryHelper {
    static func existingObserver(for viewController: UIViewController, identifier: AnyObject) -> Any? {
        if PerformanceMonitoring.experiments.observersOnBackgroundQueue {
            let tPointer = unsafeBitCast(identifier, to: UnsafeRawPointer.self)
            if let result = objc_getAssociatedObject(viewController, tPointer) {
                return result
            }
        } else {
            var vc: UIViewController? = viewController
            while let current = vc {
                let tPointer = unsafeBitCast(identifier, to: UnsafeRawPointer.self)
                if let result = objc_getAssociatedObject(current, tPointer) {
                    return result
                }
                vc = current.parent
            }
        }

        return nil
    }

    static func existingObserver(forChild viewController: UIViewController, identifier: AnyObject) -> Any? {
        var vc: UIViewController? = viewController
        while let current = vc {
            let tPointer = unsafeBitCast(identifier, to: UnsafeRawPointer.self)
            if let result = objc_getAssociatedObject(current, tPointer) {
                return result
            }
            vc = current.parent
        }
        return nil
    }
}
