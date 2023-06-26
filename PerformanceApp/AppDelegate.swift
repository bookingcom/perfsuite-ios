//
//  PerformanceAppApp.swift
//  PerformanceApp
//
//  Created by Gleb Tarasov on 30/11/2021.
//

import PerformanceSuite
import SwiftUI
import UIKit

@main
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        do {
            try PerformanceSuite.enable(config: .all(receiver: MetricsConsumerImpl()))
        } catch {
            preconditionFailure("Couldn't initialize PerformanceSuite: \(error)")
        }

        let tc = UITabBarController()
        tc.viewControllers = [makeMenuController()] + makeTabs()

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = tc
        window.makeKeyAndVisible()
        window.backgroundColor = .red
        self.window = window
        return true
    }

    func makeMenuController() -> UIViewController {
        let menu = UINavigationController(rootViewController: RootController())
        menu.tabBarItem = UITabBarItem(title: "Menu", image: nil, tag: 0)
        return menu
    }

    func makeTabs() -> [UIViewController] {
        [ListMode.delay3s, ListMode.delay5s].map { mode in
            let vc = UIHostingController(rootView: ListView(mode: mode))
            let title = mode.title.components(separatedBy: .whitespaces)[0...1].joined(separator: " ")
            vc.tabBarItem = UITabBarItem(title: title, image: nil, tag: mode.title.hash)
            return vc
        }
    }


    var window: UIWindow?
}

class MetricsConsumerImpl: PerformanceSuiteMetricsReceiver {

    func appRenderingMetricsReceived(metrics: RenderingMetrics) {
        debugPrint("App RenderingMetrics \(metrics)")
    }

    func ttiMetricsReceived(metrics: TTIMetrics, viewController: UIViewController) {
        if let introspectable = viewController as? RootViewIntrospectable {
            let view = introspectable.introspectRootView()
            let viewType = type(of: view)
            debugPrint("TTIMetrics \(viewType) \(metrics)")
        } else {
            debugPrint("TTIMetrics \(type(of: viewController)) \(metrics)")
        }
    }

    func renderingMetricsReceived(metrics: RenderingMetrics, viewController: UIViewController) {
        let screen: String
        if let introspectable = viewController as? RootViewIntrospectable {
            let view = introspectable.introspectRootView()
            let viewType = type(of: view)
            screen = String(describing: viewType)
        } else {
            screen = String(describing: type(of: viewController))
        }
        debugPrint("RenderingMetrics \(screen) \(metrics)")
    }

    func shouldTrack(viewController: UIViewController) -> Bool {
        if let introspectable = viewController as? RootViewIntrospectable {
            let view = introspectable.introspectRootView()
            switch view {
            case is RootView,
                is ListView,
                is MemoryLeakView:
                return true
            default:
                fatalError("Unknown root view \(type(of: view))")
            }
        }
        return false
    }

    func watchdogTerminationReceived(_ data: WatchdogTerminationData) {
        debugPrint("WatchdogTermination reported")
    }

    func fatalHangReceived() {
        debugPrint("Fatal hang reported")
    }

    func nonFatalHangReceived(duration: DispatchTimeInterval) {
        debugPrint("Non-fatal hang reported with duration \(duration.seconds ?? 0)")
    }

    func startupFatalHangReceived() {
        debugPrint("Startup fatal hang reported")
    }

    func viewControllerLeakReceived(viewController: UIViewController) {
        debugPrint("View controller leak \(viewController)")
    }

    func startupTimeReceived(_ data: StartupTimeData) {
        debugPrint("Startup time received \(data.totalTime.milliseconds ?? 0) ms")
    }

    func fragmentTTIMetricsReceived(metrics: TTIMetrics, identifier: String) {
        debugPrint("fragmentTTIMetricsReceived \(identifier) \(metrics)")
    }

    func fatalHangReceived(info: HangInfo) {
        debugPrint("fatalHangReceived \(info)")
    }

    func nonFatalHangReceived(info: HangInfo) {
        debugPrint("nonFatalHangReceived \(info)")
    }

    func hangStarted(info: HangInfo) {
        debugPrint("hangStarted \(info)")
    }

    // MARK: - ViewControllerLoggingReceiver

    func key(for viewController: UIViewController) -> String {
        return String(describing: viewController)
    }

    func onInit(viewControllerKey: String) {
        debugPrint("onInit \(viewControllerKey)")
    }

    func onViewDidLoad(viewControllerKey: String) {
        debugPrint("onViewDidLoad \(viewControllerKey)")
    }

    func onViewWillAppear(viewControllerKey: String) {
        debugPrint("onViewWillAppear \(viewControllerKey)")
    }

    func onViewDidAppear(viewControllerKey: String) {
        debugPrint("onViewDidAppear \(viewControllerKey)")
    }

    func onViewWillDisappear(viewControllerKey: String) {
        debugPrint("onViewWillDisappear \(viewControllerKey)")
    }

    func onViewDidDisappear(viewControllerKey: String) {
        debugPrint("onViewDidDisappear \(viewControllerKey)")
    }
}
