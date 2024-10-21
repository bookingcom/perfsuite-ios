//
//  Observer.swift
//  Pods
//
//  Created by Gleb Tarasov on 19/10/2024.
//

@testable import PerformanceSuite
import UIKit

enum ObserverMethods: Equatable {
    case beforeInit
    case beforeViewDidLoad
    case afterViewWillAppear
    case afterViewDidAppear
    case beforeViewWillDisappear
    case beforeViewDidDisappear
}

class Observer: ViewControllerObserver {

    func beforeInit(viewController: UIViewController) {
        self.viewController = viewController
        lastMethod = .beforeInit
        lastTime = DispatchTime.now()
    }

    func beforeViewDidLoad(viewController: UIViewController) {
        self.viewController = viewController
        lastMethod = .beforeViewDidLoad
        lastTime = DispatchTime.now()
    }

    func afterViewDidAppear(viewController: UIViewController) {
        self.viewController = viewController
        lastMethod = .afterViewDidAppear
        lastTime = DispatchTime.now()
    }

    func afterViewWillAppear(viewController: UIViewController) {
        self.viewController = viewController
        lastMethod = .afterViewWillAppear
        lastTime = DispatchTime.now()
    }

    func beforeViewWillDisappear(viewController: UIViewController) {
        self.viewController = viewController
        lastMethod = .beforeViewWillDisappear
        lastTime = DispatchTime.now()
    }

    func beforeViewDidDisappear(viewController: UIViewController) {
        self.viewController = viewController
        lastMethod = .beforeViewDidDisappear
        lastTime = DispatchTime.now()
    }

    static let identifier: AnyObject = NSObject()

    func clear() {
        viewController = nil
        lastMethod = nil
        lastTime = nil
    }

    var viewController: UIViewController?
    var lastMethod: ObserverMethods?
    var lastTime: DispatchTime?
}

class InstanceObserver: ViewControllerInstanceObserver {
    func beforeInit() {
        lastMethod = .beforeInit
        lastTime = DispatchTime.now()
    }

    func beforeViewDidLoad() {
        lastMethod = .beforeViewDidLoad
        lastTime = DispatchTime.now()
    }

    func afterViewWillAppear() {
        lastMethod = .afterViewWillAppear
        lastTime = DispatchTime.now()
    }

    func afterViewDidAppear() {
        lastMethod = .afterViewDidAppear
        lastTime = DispatchTime.now()
    }

    func beforeViewWillDisappear() {
        lastMethod = .beforeViewWillDisappear
        lastTime = DispatchTime.now()
    }

    static let identifier: AnyObject = NSObject()

    func clear() {
        lastMethod = nil
        lastTime = nil
    }

    var viewController: UIViewController?
    var lastMethod: ObserverMethods?
    var lastTime: DispatchTime?

    required init(viewController: UIViewController?) {
        lastObserverCreated = self
        self.viewController = viewController
    }
}

var lastObserverCreated: InstanceObserver?
