//
//  ViewControllerSubscriber.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 06/07/2021.
//

import UIKit


/// Singleton class to swizzle UIViewController methods and add calling methods of the single main `ViewControllerObserver`.
final class ViewControllerSubscriber {

    static let shared = ViewControllerSubscriber()

    // UIViewController methods
    private let classToSwizzle = UIViewController.self
    private let initWithCoderSelector = #selector(UIViewController.init(coder:))
    private let initWithNibSelector = #selector(UIViewController.init(nibName:bundle:))
    private let viewDidLoadSelector = #selector(UIViewController.viewDidLoad)
    private let viewWillAppearSelector = #selector(UIViewController.viewWillAppear(_:))
    private let viewDidAppearSelector = #selector(UIViewController.viewDidAppear(_:))
    private let viewWillDisappearSelector = #selector(UIViewController.viewWillDisappear(_:))
    private let viewDidDisappearSelector = #selector(UIViewController.viewDidDisappear(_:))

    func subscribeObserver(_ observer: ViewControllerObserver) throws {
        try Swizzler.swizzle(class: classToSwizzle, selector: initWithNibSelector) { (vc: UIViewController) in
            observer.beforeInit(viewController: vc)
        }

        try Swizzler.swizzle(class: classToSwizzle, selector: initWithCoderSelector) { (vc: UIViewController) in
            observer.beforeInit(viewController: vc)
        }

        try Swizzler.swizzle(class: classToSwizzle, selector: viewDidLoadSelector) { (vc: UIViewController) in
            observer.beforeViewDidLoad(viewController: vc)
        }

        try Swizzler.swizzle(class: classToSwizzle, selector: viewWillAppearSelector) { (vc: UIViewController) in
            DispatchQueue.main.async {
                observer.afterViewWillAppear(viewController: vc)
            }
        }

        try Swizzler.swizzle(class: classToSwizzle, selector: viewDidAppearSelector) { (vc: UIViewController) in
            DispatchQueue.main.async {
                observer.afterViewDidAppear(viewController: vc)
            }
        }

        try Swizzler.swizzle(class: classToSwizzle, selector: viewWillDisappearSelector) { (vc: UIViewController) in
            observer.beforeViewWillDisappear(viewController: vc)
        }

        try Swizzler.swizzle(class: classToSwizzle, selector: viewDidDisappearSelector) { (vc: UIViewController) in
            observer.beforeViewDidDisappear(viewController: vc)
        }
    }

    func unsubscribeObservers() throws {
        try Swizzler.unswizzle(class: classToSwizzle, selector: initWithNibSelector)
        try Swizzler.unswizzle(class: classToSwizzle, selector: initWithCoderSelector)
        try Swizzler.unswizzle(class: classToSwizzle, selector: viewDidLoadSelector)
        try Swizzler.unswizzle(class: classToSwizzle, selector: viewWillAppearSelector)
        try Swizzler.unswizzle(class: classToSwizzle, selector: viewDidAppearSelector)
        try Swizzler.unswizzle(class: classToSwizzle, selector: viewWillDisappearSelector)
        try Swizzler.unswizzle(class: classToSwizzle, selector: viewDidDisappearSelector)
    }
}
