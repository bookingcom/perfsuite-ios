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
public protocol ViewControllerLoggingReceiver: ScreenMetricsReceiver {

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

    /// Method is called during view controller's `viewDidDisappear`
    func onViewDidDisappear(screen: ScreenIdentifier)
}


/// Observer which forward all delegate methods to its receiver for logging purposes
final class LoggingObserver<V: ViewControllerLoggingReceiver>: ViewControllerObserver {

    init(screen: V.ScreenIdentifier, receiver: V) {
        self.screen = screen
        self.receiver = receiver
    }

    private let screen: V.ScreenIdentifier
    private let receiver: V


    func beforeInit(viewController: UIViewController) {
        PerformanceMonitoring.consumerQueue.async {
            self.receiver.onInit(screen: self.screen)
        }
    }

    func beforeViewDidLoad(viewController: UIViewController) {
        PerformanceMonitoring.consumerQueue.async {
            self.receiver.onViewDidLoad(screen: self.screen)
        }
    }

    func afterViewWillAppear(viewController: UIViewController) {
        PerformanceMonitoring.consumerQueue.async {
            self.receiver.onViewWillAppear(screen: self.screen)
        }
    }

    func afterViewDidAppear(viewController: UIViewController) {
        rememberOpenedScreenIfNeeded(viewController)
        PerformanceMonitoring.consumerQueue.async {
            self.receiver.onViewDidAppear(screen: self.screen)
        }
    }

    func beforeViewWillDisappear(viewController: UIViewController) {
        PerformanceMonitoring.consumerQueue.async {
            self.receiver.onViewWillDisappear(screen: self.screen)
        }
    }

    func beforeViewDidDisappear(viewController: UIViewController) {
        PerformanceMonitoring.consumerQueue.async {
            self.receiver.onViewDidDisappear(screen: self.screen)
        }
    }

    static var identifier: AnyObject {
        return loggingObserverIdentifier
    }

    // MARK: - Top screen detection

    private func rememberOpenedScreenIfNeeded(_ viewController: UIViewController) {
        if PerformanceMonitoring.experiments.observersOnBackgroundQueue {
            DispatchQueue.main.async {
                guard self.isTopScreen(viewController) else {
                    return
                }
                PerformanceMonitoring.queue.async {
                    let description = RootViewIntrospection.shared.description(viewController: viewController)
                    AppInfoHolder.screenOpened(description)
                }
            }
        } else {
            guard isTopScreen(viewController) else {
                return
            }
            let description = RootViewIntrospection.shared.description(viewController: viewController)
            AppInfoHolder.screenOpened(description)
        }
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

private let loggingObserverIdentifier = NSObject()

// We cannot check `viewController is UIHostingController` because of generics,
// so we use helper protocol here
protocol HostingControllerIdentifier { }
extension UIHostingController: HostingControllerIdentifier { }
