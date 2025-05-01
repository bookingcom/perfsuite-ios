//
//  TopScreen.swift
//  Pods
//
//  Created by Gleb Tarasov on 5/1/25.
//

import SwiftUI
import UIKit

/// Determines if the given view controller is the top screen in the view hierarchy.
/// 
/// This function checks several conditions to determine if the specified `UIViewController`
/// is considered the top screen. It asserts that the function is called on the main thread.
/// The function returns `false` if:
/// - The view controller is a container controller.
/// - The view controller has a parent that is not a container controller.
/// - The view controller is a UIKit controller.
/// - The view controller is inside a cell.
/// - The view controller is used for navigation bar buttons.
///
/// - Parameter viewController: The `UIViewController` to check.
/// - Returns: `true` if the view controller is the top screen, `false` otherwise.
public func isTopScreen(_ viewController: UIViewController) -> Bool {
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

private let uiKitBundle = Bundle(for: UIViewController.self)
private let uiKitContainers = [
    UINavigationController.self,
    UITabBarController.self,
    UISplitViewController.self,
    UIPageViewController.self,
]

// We cannot check `viewController is UIHostingController` because of generics,
// so we use helper protocol here
protocol HostingControllerIdentifier { }
extension UIHostingController: HostingControllerIdentifier { }
