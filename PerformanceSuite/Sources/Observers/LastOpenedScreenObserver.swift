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
            guard isTopScreen(viewController) else {
                return
            }
            if PerformanceMonitoring.experiments.releaseViewControllersOnMain {
                // releaseViewControllersOnMain: variant implementation; keep on cleanup.
                PerformanceMonitoring.queue.asyncReleasingOnMain(viewController) {
                    let description = RootViewIntrospection.shared.description(viewController: $0)
                    AppInfoHolder.screenOpened(description)
                }
            } else {
                // releaseViewControllersOnMain: base implementation; remove on cleanup.
                PerformanceMonitoring.queue.async {
                    let description = RootViewIntrospection.shared.description(viewController: viewController)
                    AppInfoHolder.screenOpened(description)
                }
            }
        }
    }
}
