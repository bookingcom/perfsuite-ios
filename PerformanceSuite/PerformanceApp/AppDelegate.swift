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

        let didCrash = CrashesInterceptor.didCrashDuringPreviousLaunch()
        CrashesInterceptor.interceptCrashes()

        UITestsHelper.prepareForTestsIfNeeded()

        do {
            try PerformanceMonitoring.enable(config: .all(receiver: MetricsConsumer()), didCrashPreviously: didCrash)
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
