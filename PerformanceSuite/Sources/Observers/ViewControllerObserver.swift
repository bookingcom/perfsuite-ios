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

    // releaseViewControllersOnMain: keep on cleanup.
    /// Called once on `PerformanceMonitoring.queue` right after the observer is created, while the caller holds `viewController`.
    func didCreate(for viewController: UIViewController)

    static var identifier: AnyObject { get }
}

extension ViewControllerInstanceObserver {
    // releaseViewControllersOnMain: keep on cleanup.
    func didCreate(for viewController: UIViewController) { }
}


/// Observer which creates separate `ViewControllerObserver` for every view controller
final class ViewControllerObserverFactory<T: ViewControllerInstanceObserver, S: ScreenMetricsReceiver>: ViewControllerObserver {

    required init(metricsReceiver: S, observerMaker: @escaping (S.ScreenIdentifier) -> T) {
        self.metricsReceiver = metricsReceiver
        self.observerMaker = observerMaker
    }
    private let metricsReceiver: S
    private let observerMaker: (S.ScreenIdentifier) -> T

    // releaseViewControllersOnMain: remove on cleanup.
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
        if PerformanceMonitoring.experiments.releaseViewControllersOnMain {
            // releaseViewControllersOnMain: variant implementation; keep on cleanup.
            observer.didCreate(for: viewController)
        }
        return observer
    }

    func beforeInit(viewController: UIViewController) {
        if PerformanceMonitoring.experiments.releaseViewControllersOnMain {
            // releaseViewControllersOnMain: variant implementation; keep on cleanup.
            PerformanceMonitoring.queue.asyncReleasingOnMain(viewController) { self.observer(for: $0)?.beforeInit() }
        } else {
            // releaseViewControllersOnMain: base implementation; remove on cleanup.
            PerformanceMonitoring.queue.async {
                self.observer(for: viewController)?.beforeInit()
                self.ensureDeallocationOnTheMainThread(viewController: viewController)
            }
        }
    }

    func beforeViewDidLoad(viewController: UIViewController) {
        if PerformanceMonitoring.experiments.releaseViewControllersOnMain {
            // releaseViewControllersOnMain: variant implementation; keep on cleanup.
            PerformanceMonitoring.queue.asyncReleasingOnMain(viewController) { self.observer(for: $0)?.beforeViewDidLoad() }
        } else {
            // releaseViewControllersOnMain: base implementation; remove on cleanup.
            PerformanceMonitoring.queue.async {
                self.observer(for: viewController)?.beforeViewDidLoad()
                self.ensureDeallocationOnTheMainThread(viewController: viewController)
            }
        }
    }

    func afterViewDidAppear(viewController: UIViewController) {
        if PerformanceMonitoring.experiments.releaseViewControllersOnMain {
            // releaseViewControllersOnMain: variant implementation; keep on cleanup.
            PerformanceMonitoring.queue.asyncReleasingOnMain(viewController) { self.observer(for: $0)?.afterViewDidAppear() }
        } else {
            // releaseViewControllersOnMain: base implementation; remove on cleanup.
            PerformanceMonitoring.queue.async {
                self.observer(for: viewController)?.afterViewDidAppear()
                self.ensureDeallocationOnTheMainThread(viewController: viewController)
            }
        }
    }

    func beforeViewWillDisappear(viewController: UIViewController) {
        if PerformanceMonitoring.experiments.releaseViewControllersOnMain {
            // releaseViewControllersOnMain: variant implementation; keep on cleanup.
            PerformanceMonitoring.queue.asyncReleasingOnMain(viewController) { self.observer(for: $0)?.beforeViewWillDisappear() }
        } else {
            // releaseViewControllersOnMain: base implementation; remove on cleanup.
            PerformanceMonitoring.queue.async {
                self.observer(for: viewController)?.beforeViewWillDisappear()
                self.ensureDeallocationOnTheMainThread(viewController: viewController)
            }
        }
    }

    func afterViewWillAppear(viewController: UIViewController) {
        if PerformanceMonitoring.experiments.releaseViewControllersOnMain {
            // releaseViewControllersOnMain: variant implementation; keep on cleanup.
            PerformanceMonitoring.queue.asyncReleasingOnMain(viewController) { self.observer(for: $0)?.afterViewWillAppear() }
        } else {
            // releaseViewControllersOnMain: base implementation; remove on cleanup.
            PerformanceMonitoring.queue.async {
                self.observer(for: viewController)?.afterViewWillAppear()
                self.ensureDeallocationOnTheMainThread(viewController: viewController)
            }
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

extension DispatchQueue {
    /// Runs `work` with `viewController` on this queue without this queue ever owning it.
    ///
    /// UIKit marks a view controller as deallocating when its last reference is released off main, but runs
    /// `dealloc` later on main. If its view leaves the window in between, `viewDidMoveToWindow:shouldAppearOrDisappear:`
    /// forms a weak reference to it and the app aborts. So the only extra retain is taken here, on the calling thread,
    /// and released on main after `work` returns: `work` borrows the view controller and can never release it last.
    func asyncReleasingOnMain(_ viewController: UIViewController, _ work: @escaping (UIViewController) -> Void) {
        let reference = Unmanaged.passRetained(viewController)
        async {
            work(reference.takeUnretainedValue())
            DispatchQueue.main.async {
                reference.release()
            }
        }
    }
}
