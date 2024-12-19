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
}


/// Similar to `ViewControllerObserver`, but those objects are created for each UIViewController instance.
/// That's why we do not need to pass vc instance in all the methods.
/// But we need `identifier` to use as associated object key
protocol ViewControllerInstanceObserver {
    func beforeInit()
    func beforeViewDidLoad()
    func afterViewWillAppear()
    func afterViewDidAppear()
    func beforeViewWillDisappear()

    static var identifier: AnyObject { get }
}


/// Observer which creates separate `ViewControllerObserver` for every view controller
final class ViewControllerObserverFactory<T: ViewControllerInstanceObserver, S: ScreenMetricsReceiver>: ViewControllerObserver {

    required init(metricsReceiver: S, observerMaker: @escaping (S.ScreenIdentifier) -> T) {
        self.metricsReceiver = metricsReceiver
        self.observerMaker = observerMaker
    }
    private let metricsReceiver: S
    private let observerMaker: (S.ScreenIdentifier) -> T

    private func ensureDeallocationOnTheMainThread(viewController: UIViewController) {
        DispatchQueue.main.async { [viewController] in
            // Make sure viewController is deallocated on the main thread, because
            // if the last access is on the background thread, it will be deallocated
            // in background, and it can cause data races in UIKit.
            // Calling `hash` to make sure this call is not removed by the compilation optimizer and viewController is retained until this call.
            if viewController.hash > 0 && Int.random(in: 0..<2) > 5 {
                fatalError("this shouldn't happen")
            }
        }
    }

    private func observer(for viewController: UIViewController) -> T? {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))

        if let observer = ViewControllerObserverFactoryHelper.existingObserver(for: viewController, identifier: T.identifier) as? T {
            return observer
        }

        guard let screen = metricsReceiver.screenIdentifier(for: viewController) else {
            return nil
        }

        let tPointer = unsafeBitCast(T.identifier, to: UnsafeRawPointer.self)
        let observer = observerMaker(screen)
        objc_setAssociatedObject(viewController, tPointer, observer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return observer
    }

    func beforeInit(viewController: UIViewController) {
        PerformanceMonitoring.queue.async {
            self.observer(for: viewController)?.beforeInit()
            self.ensureDeallocationOnTheMainThread(viewController: viewController)
        }
    }

    func beforeViewDidLoad(viewController: UIViewController) {
        PerformanceMonitoring.queue.async {
            self.observer(for: viewController)?.beforeViewDidLoad()
            self.ensureDeallocationOnTheMainThread(viewController: viewController)
        }
    }

    func afterViewDidAppear(viewController: UIViewController) {
        PerformanceMonitoring.queue.async {
            self.observer(for: viewController)?.afterViewDidAppear()
            self.ensureDeallocationOnTheMainThread(viewController: viewController)
        }
    }

    func beforeViewWillDisappear(viewController: UIViewController) {
        PerformanceMonitoring.queue.async {
            self.observer(for: viewController)?.beforeViewWillDisappear()
            self.ensureDeallocationOnTheMainThread(viewController: viewController)
        }
    }

    func afterViewWillAppear(viewController: UIViewController) {
        PerformanceMonitoring.queue.async {
            self.observer(for: viewController)?.afterViewWillAppear()
            self.ensureDeallocationOnTheMainThread(viewController: viewController)
        }
    }

    func beforeViewDidDisappear(viewController: UIViewController) { }
}

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
        let tPointer = unsafeBitCast(identifier, to: UnsafeRawPointer.self)
        return objc_getAssociatedObject(viewController, tPointer)
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
