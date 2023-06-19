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
public protocol ViewControllerLoggingReceiver: AnyObject {

    /// Getting the string key for a view controller which later will be passed to other methods.
    /// Method is executed on the main thread, should be as performant as possible.
    func key(for viewController: UIViewController) -> String

    /// Method is called during view controller's initialization
    func onInit(viewControllerKey: String)

    /// Method is called during view controller's `viewDidLoad`
    func onViewDidLoad(viewControllerKey: String)

    /// Method is called during view controller's `viewWillAppear`
    func onViewWillAppear(viewControllerKey: String)

    /// Method is called during view controller's `viewDidAppear`
    func onViewDidAppear(viewControllerKey: String)

    /// Method is called during view controller's `viewWillDisappear`
    func onViewWillDisappear(viewControllerKey: String)

    /// Method is called during view controller's `viewDidDisappear`
    func onViewDidDisappear(viewControllerKey: String)
}


/// Observer which forward all delegate methods to its receiver for logging purposes
final class LoggingObserver: ViewControllerObserver {

    init(receiver: ViewControllerLoggingReceiver) {
        self.receiver = receiver
    }

    private var receiver: ViewControllerLoggingReceiver?

    func beforeInit(viewController: UIViewController) {
        guard let key = self.receiver?.key(for: viewController) else {
            return
        }
        PerformanceSuite.consumerQueue.async {
            self.receiver?.onInit(viewControllerKey: key)
        }
    }

    func beforeViewDidLoad(viewController: UIViewController) {
        guard let key = self.receiver?.key(for: viewController) else {
            return
        }
        PerformanceSuite.consumerQueue.async {
            self.receiver?.onViewDidLoad(viewControllerKey: key)
        }
    }

    func afterViewWillAppear(viewController: UIViewController) {
        guard let key = self.receiver?.key(for: viewController) else {
            return
        }
        PerformanceSuite.consumerQueue.async {
            self.receiver?.onViewWillAppear(viewControllerKey: key)
        }
    }

    func afterViewDidAppear(viewController: UIViewController) {
        guard let key = self.receiver?.key(for: viewController) else {
            return
        }
        rememberOpenedScreenIfNeeded(viewController)
        PerformanceSuite.consumerQueue.async {
            self.receiver?.onViewDidAppear(viewControllerKey: key)
        }
    }

    func beforeViewWillDisappear(viewController: UIViewController) {
        guard let key = self.receiver?.key(for: viewController) else {
            return
        }
        PerformanceSuite.consumerQueue.async {
            self.receiver?.onViewWillDisappear(viewControllerKey: key)
        }
    }

    func beforeViewDidDisappear(viewController: UIViewController) {
        guard let key = self.receiver?.key(for: viewController) else {
            return
        }
        PerformanceSuite.consumerQueue.async {
            self.receiver?.onViewDidDisappear(viewControllerKey: key)
        }
    }

    // MARK: - Top screen detection

    private func rememberOpenedScreenIfNeeded(_ viewController: UIViewController) {
        guard isTopScreen(viewController) else {
            return
        }
        let description: String
        if let introspectable = viewController as? RootViewIntrospectable {
            // For SwiftUI hosting controller we are trying to find a root view, not the controller itself.
            // This is happening only on a new screen appearance, so shouldn't affect performance a lot.
            description = String(describing: type(of: introspectable.introspectRootView()))
        } else {
            description = type(of: viewController).description()
        }
        AppInfoHolder.screenOpened(description)
    }

    private func isTopScreen(_ viewController: UIViewController) -> Bool {
        assert(Thread.isMainThread)

        // if our class is a container - skip it
        if isContainerController(viewController) {
            return false
        }

        // if we have a parent, which is not a container controller -> this is not a top screen
        if let parent = viewController.parent {
            if !isContainerController(parent) {
                return false
            }
        }

        // skip all UIKit controllers
        if isUIKitController(viewController) {
            return false
        }

        // this is a controller inside a cell
        if isCellSubview(viewController.view) || isCellSubview(viewController.view.superview) {
            return false
        }

        // there are UIHostingControllers used for navigation bar buttons. Ignore them too
        if isNavigationBarSubview(viewController.view) {
            return false
        }

        return true
    }

    private func isUIKitController(_ viewController: UIViewController) -> Bool {
        // we do not consider UIHostingController as UIKit controller,
        // because inside it contains our custom SwiftUI views
        if viewController is HostingControllerIdentifier {
            return false
        }
        let viewControllerBundle = Bundle(for: type(of: viewController))
        return viewControllerBundle == uiKitBundle
    }

    private func isContainerController(_ viewController: UIViewController) -> Bool {
        let vcType = type(of: viewController)
        return uiKitContainers.contains {
            vcType.isSubclass(of: $0)
        }
    }

    private func isCellSubview(_ view: UIView?) -> Bool {
        guard let view = view else {
            return false
        }

        if view.superview is UITableViewCell {
            return true
        }

        return false
    }

    private func isNavigationBarSubview(_ view: UIView?) -> Bool {
        if view == nil {
            return false
        }

        if view is UINavigationBar {
            return true
        }

        return isNavigationBarSubview(view?.superview)
    }

    private lazy var uiKitBundle = Bundle(for: UIViewController.self)
    private lazy var uiKitContainers = [
        UINavigationController.self,
        UITabBarController.self,
        UISplitViewController.self,
        UIPageViewController.self,
    ]

}

// We cannot check `viewController is UIHostingController` because of generics,
// so we use helper protocol here
protocol HostingControllerIdentifier { }
extension UIHostingController: HostingControllerIdentifier { }
