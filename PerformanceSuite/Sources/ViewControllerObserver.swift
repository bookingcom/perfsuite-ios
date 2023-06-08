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

/// Observer which creates separate `ViewControllerObserver` for every view controller
final class ViewControllerObserverFactory<T: ViewControllerObserver>: ViewControllerObserver {

    required init(metricsReceiver: ScreenMetricsReceiver, observerMaker: @escaping () -> T) {
        self.metricsReceiver = metricsReceiver
        self.observerMaker = observerMaker
    }
    private let metricsReceiver: ScreenMetricsReceiver
    private let observerMaker: () -> T

    static func existingObserver(for viewController: UIViewController) -> T? {
        var vc: UIViewController? = viewController
        while let current = vc {
            let tPointer = unsafeBitCast(T.self, to: UnsafeRawPointer.self)
            if let result = objc_getAssociatedObject(current, tPointer) as? T {
                return result
            }
            vc = current.parent
        }
            
        return nil
    }

    private func observer(for viewController: UIViewController) -> T? {

        guard metricsReceiver.shouldTrack(viewController: viewController) else {
            return nil
        }

        if let observer = Self.existingObserver(for: viewController) {
            return observer
        }

        let tPointer = unsafeBitCast(T.self, to: UnsafeRawPointer.self)
        let observer = observerMaker()
        objc_setAssociatedObject(viewController, tPointer, observer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return observer
    }

    func beforeInit(viewController: UIViewController) {
        observer(for: viewController)?.beforeInit(viewController: viewController)
    }

    func beforeViewDidLoad(viewController: UIViewController) {
        observer(for: viewController)?.beforeViewDidLoad(viewController: viewController)
    }

    func afterViewDidAppear(viewController: UIViewController) {
        observer(for: viewController)?.afterViewDidAppear(viewController: viewController)
    }

    func beforeViewWillDisappear(viewController: UIViewController) {
        observer(for: viewController)?.beforeViewWillDisappear(viewController: viewController)
    }

    func afterViewWillAppear(viewController: UIViewController) {
        observer(for: viewController)?.afterViewWillAppear(viewController: viewController)
    }

    func beforeViewDidDisappear(viewController: UIViewController) {
        observer(for: viewController)?.beforeViewDidDisappear(viewController: viewController)
    }
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
}
