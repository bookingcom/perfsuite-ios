//
//  ViewControllerLeaksObserver.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 15/02/2022.
//

import Foundation
import UIKit

/// We mark UIViewController or the root SwiftUI view inside UIHostingController with this protocol to be ignored in `ViewControllerLeaksReceiver`
public protocol LeakCheckDisabled {}

/// This is the analogue of `LeakCheckDisabled` which can be used in Obj-C code for marking UIViewControllers.
@objc public protocol ObjcLeakCheckDisabled: AnyObject {}


public protocol ViewControllerLeaksReceiver {

    /// View controller wasn't deallocated after viewDidDisappear method was called.
    /// For most of the cases it means the leak, but for some cases this behavior is valid
    /// (for example if you have reuse pool for view controllers in something like UIPageViewController).
    /// To silent those messages for some of your controllers, mark those controllers with the protocol `LeakCheckDisabled`.
    func viewControllerLeakReceived(viewController: UIViewController)
}

/// Observer checks if view controllers are deallocated some time after `viewDidDisappear`
///
/// The initial idea is taken from http://holko.pl/2017/06/26/checking-uiviewcontroller-deallocation/
final class ViewControllerLeaksObserver: ViewControllerObserver {

    private let metricsReceiver: ViewControllerLeaksReceiver
    private let detectionTimeout: DispatchTimeInterval
    private var viewControllersToHandle: Set<ObjectIdentifier> = []

    init(metricsReceiver: ViewControllerLeaksReceiver, detectionTimeout: DispatchTimeInterval = .seconds(2)) {
        self.metricsReceiver = metricsReceiver
        self.detectionTimeout = detectionTimeout
    }

    // MARK: - ViewControllerObserver

    func beforeInit(viewController: UIViewController) {}
    func beforeViewDidLoad(viewController: UIViewController) {}
    func afterViewWillAppear(viewController: UIViewController) {}
    func afterViewDidAppear(viewController: UIViewController) {}
    func beforeViewWillDisappear(viewController: UIViewController) {
        // We separate detection logic by 2 parts:
        // In the viewWillDisappear we check if we should handle view controller at all.
        // We skip all the exceptions.
        //
        // In the viewDidDisappear we perform the actual check.
        //
        // We need to stages, because in in viewDidDisappear viewController.parent can be already nil,
        // so we cannot properly check for the exceptions, since we iterate though the vc hierarchy.
        assert(Thread.isMainThread)
        let isMovingFromParent = viewController.isMovingFromParent
        let isBeingDismissed = viewController.isBeingDismissed
        guard isMovingFromParent || isBeingDismissed else {
            // We check only cases when we dismiss view controller, or go back in navigation stack.
            // Ignore cases when view controller disappeared because we went forward or presented a new view controller.
            // This check also avoids false-alerts for view controllers inside UITabBarController.
            return
        }

        if isKnownException(viewController) {
            // this is the hard coded exception, ignore it
            return
        }
        if isMarkedAsException(viewController) {
            // this is the exception marked by a developer, ignore it
            return
        }

        viewControllersToHandle.insert(ObjectIdentifier(viewController))
    }

    func beforeViewDidDisappear(viewController: UIViewController) {
        assert(Thread.isMainThread)
        let identifier = ObjectIdentifier(viewController)
        guard viewControllersToHandle.contains(identifier) else {
            return
        }
        viewControllersToHandle.remove(identifier)

        // We will come here only for view controller which is root in disappearing stack,
        // but some child controller may leak too, that's why we call `checkDeallocation` for all the child controllers.
        let allViewControllers = selfAndAllChildren(viewController: viewController)
            .filter { vc in
                if isKnownException(vc) {
                    // this is the hard coded exception, ignore it
                    return false
                }
                if isMarkedAsException(vc) {
                    // this is the exception marked by a developer, ignore it
                    return false
                }
                return true
            }
            .map(WeakViewController.init(_:))

        let isMovingFromParent = viewController.isMovingFromParent
        DispatchQueue.main.asyncAfter(deadline: .now() + detectionTimeout) {
            for weakViewController in allViewControllers {
                self.checkDeallocation(viewController: weakViewController.viewController, isMovingFromParent: isMovingFromParent)
            }
        }
    }

    // MARK: - Helpers

    private func selfAndAllChildren(viewController: UIViewController) -> [UIViewController] {
        return [viewController] + viewController.children.flatMap(selfAndAllChildren(viewController:))
    }

    private func checkDeallocation(viewController: UIViewController?, isMovingFromParent: Bool) {
        guard let viewController = viewController else {
            return
        }

        if viewController.isViewLoaded && viewController.view.window != nil {
            // View controller re-appeared again, ignore this vc.
            return
        }

        if isMovingFromParent && viewController.parent != nil {
            // Was moving from parent, but still has a parent. Most often happens for
            // view controllers made by UIViewControllerRepresentable SwiftUI Views.
            // Ignore this vc.
            return
        }

        PerformanceMonitoring.consumerQueue.async {
            self.metricsReceiver.viewControllerLeakReceived(viewController: viewController)
        }
    }

    private func isKnownException(_ viewController: UIViewController) -> Bool {
        // here we enumerate all known view controllers from Apple frameworks that are known to be not deallocated after viewDidDisappear
        if viewController is UIImagePickerController {
            // image picker doesn't seem to always be released
            return true
        }

        if viewController is UISearchController || viewController.parent is UISearchController {
            // these are typically retained after search is dismissed
            return true
        }

        let name = type(of: viewController).description()
        if knownStringExceptions.contains(name) {
            return true
        }

        if name.hasPrefix("_UI") {
            // ignore all private UIKit controllers in one
            return true
        }

        return false
    }

    private func isMarkedAsException(_ viewController: UIViewController) -> Bool {
        if viewController is LeakCheckDisabled || viewController is ObjcLeakCheckDisabled {
            // view controller is marked to be ignored, no need to assert, ignore it.
            return true
        }

        // check if this is UIHostingController with a SwiftUI view
        if let rootView = (viewController as? RootViewIntrospectable)?.introspectRootView(),
            rootView is LeakCheckDisabled {
            // this view was marked to be ignored
            return true
        }

        if let parent = viewController.parent {
            return isMarkedAsException(parent)
        } else {
            return false
        }
    }

    private let knownStringExceptions: Set<String> = [
        // part of the keyboard, retained by iOS
        "UICandidateViewController",
        // part of the keyboard, retained by iOS
        "UICompatibilityInputViewController",
        // also not deallocated, no control over it
        "UIPredictionViewController",
        // Those 2 are not deallocated, but this is not under our control
        "SLComposeViewController",
        "SLRemoteComposeViewController",
    ]

    private struct WeakViewController {
        init(_ viewController: UIViewController) {
            self.viewController = viewController
        }
        weak var viewController: UIViewController?
    }
}
