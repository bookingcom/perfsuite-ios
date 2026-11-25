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
        if PerformanceMonitoring.experiments.releaseViewControllersOnMain {
            // releaseViewControllersOnMain: variant implementation; keep on cleanup.
            // Weak, so that the deferred check never keeps the view controller alive past a leak check.
            DispatchQueue.main.async { [weak viewController] in
                guard let viewController, isTopScreen(viewController) else {
                    return
                }
                // Reflecting the views copies the objects they capture, so it stays on main. Only the type names go to
                // the queue, for the slow part: parsing the generic types.
                let typeNames = RootViewIntrospection.shared.typeNames(viewController: viewController)
                PerformanceMonitoring.queue.async {
                    AppInfoHolder.screenOpened(RootViewIntrospection.shared.description(typeNames: typeNames))
                }
            }
        } else {
            // releaseViewControllersOnMain: base implementation; remove on cleanup.
            DispatchQueue.main.async {
                guard isTopScreen(viewController) else {
                    return
                }
                PerformanceMonitoring.queue.async {
                    let description = RootViewIntrospection.shared.description(viewController: viewController)
                    AppInfoHolder.screenOpened(description)
                }
            }
        }
    }
}
