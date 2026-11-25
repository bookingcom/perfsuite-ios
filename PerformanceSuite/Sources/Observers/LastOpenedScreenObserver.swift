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
                guard let introspectable = viewController as? RootViewIntrospectable else {
                    let typeName = String(describing: type(of: viewController))
                    PerformanceMonitoring.queue.async {
                        AppInfoHolder.screenOpened(RootViewIntrospection.shared.description(typeName: typeName))
                    }
                    return
                }
                // Describing the root view is slow, so it runs on the queue. The walk copies the view values and the
                // objects they capture, which the root view taken here keeps alive until it is released on main.
                let rootView = Unmanaged.passRetained(RootView(introspectable.introspectRootView()))
                PerformanceMonitoring.queue.async {
                    AppInfoHolder.screenOpened(rootView.takeUnretainedValue().description)
                    DispatchQueue.main.async {
                        rootView.release()
                    }
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

// releaseViewControllersOnMain: variant implementation; keep on cleanup.
private final class RootView {
    init(_ view: Any) {
        self.view = view
    }

    let view: Any

    /// A separate scope, so the walk's copies are gone before the root view is released.
    var description: String {
        return RootViewIntrospection.shared.description(rootView: view)
    }
}
