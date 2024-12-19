//
//  LastOpenedScreenObserver.swift
//  Pods
//
//  Created by Gleb Tarasov on 19/10/2024.
//

import SwiftUI

final class LastOpenedScreenObserver: ViewControllerObserver {
    func beforeInit(viewController: UIViewController) {}

    func beforeViewDidLoad(viewController: UIViewController) {}

    func afterViewWillAppear(viewController: UIViewController) {}

    func afterViewDidAppear(viewController: UIViewController) {
        rememberOpenedScreenIfNeeded(viewController)
    }

    func beforeViewWillDisappear(viewController: UIViewController) {}

    func beforeViewDidDisappear(viewController: UIViewController) {}

    // MARK: - Top screen detection

    private func rememberOpenedScreenIfNeeded(_ viewController: UIViewController) {
        DispatchQueue.main.async {
            guard self.isTopScreen(viewController) else {
                return
            }
            PerformanceMonitoring.queue.async {
                let description = RootViewIntrospection.shared.description(viewController: viewController)
                AppInfoHolder.screenOpened(description)
            }
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

// We cannot check `viewController is UIHostingController` because of generics,
// so we use helper protocol here
protocol HostingControllerIdentifier { }
extension UIHostingController: HostingControllerIdentifier { }
