//
//  TTIMetricsReceiverStub.swift
//  Pods
//
//  Created by Gleb Tarasov on 21/09/2024.
//

import PerformanceSuite
import UIKit

class TTIMetricsReceiverStub: TTIMetricsReceiver {

    var shouldTrack: (UIViewController) -> Bool = { _ in true }

    func ttiMetricsReceived(metrics: TTIMetrics, screen viewController: UIViewController) {
        ttiCallback(metrics, viewController)
        ttiMetrics = metrics
        lastController = viewController
    }

    func screenIdentifier(for viewController: UIViewController) -> UIViewController? {
        if viewController is UINavigationController
            || viewController is UITabBarController
            || type(of: viewController) == UIViewController.self {
            return nil
        }
        if shouldTrack(viewController) {
            return viewController
        } else {
            return nil
        }
    }

    var ttiCallback: (TTIMetrics, UIViewController) -> Void = { (_, _) in }
    var ttiMetrics: TTIMetrics?
    var lastController: UIViewController?
}
