//
//  PerformanceAppApp.swift
//  PerformanceApp
//
//  Created by Gleb Tarasov on 30/11/2021.
//

import FirebaseCore
import FirebaseCrashlytics
import PerformanceSuite
import SwiftUI
import UIKit

// In SwiftPM the Crashlytics support is a separate module; in CocoaPods it is part of
// `PerformanceSuite`. Mirror the import style used by the Crashlytics sources.
#if canImport(PerformanceSuiteCrashlytics)
import PerformanceSuiteCrashlytics
#endif

@main
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        UITestsHelper.prepareForTestsIfNeeded()

        let metricsConsumer = MetricsConsumer()
        if crashlyticsEnabled {
            startWithCrashlyticsSupport(metricsConsumer: metricsConsumer)
        } else {
            startWithCustomCrashInterceptor(metricsConsumer: metricsConsumer)
        }

        if startupBackgroundEnabled {
            // Defer the whole UI setup so the first `viewDidAppear` happens a few seconds after
            // launch. Using `asyncAfter` (not a blocking sleep) keeps the run loop free, so a
            // `press(.home)` / `activate()` round-trip issued by the UI test during this window is
            // actually processed before startup finishes — exercising the background-during-startup
            // drop path deterministically.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                self.setupWindow()
            }
        } else {
            setupWindow()
        }
        return true
    }

    private func setupWindow() {
        let tc = UITabBarController()
        tc.viewControllers = [makeMenuController(), makeRenderingController()] + makeTabs()

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = tc
        window.makeKeyAndVisible()
        window.backgroundColor = .red
        self.window = window
    }

    // MARK: - Startup variants

    private var crashlyticsEnabled: Bool {
        ProcessInfo.processInfo.environment[crashlyticsKey] != nil
    }

    private var startupBackgroundEnabled: Bool {
        ProcessInfo.processInfo.environment[startupBackgroundKey] != nil
    }

    /// Default startup: a lightweight custom crash interceptor (no Firebase).
    private func startWithCustomCrashInterceptor(metricsConsumer: MetricsConsumer) {
        let didCrash = CrashesInterceptor.didCrashDuringPreviousLaunch()
        CrashesInterceptor.interceptCrashes()

        do {
            try PerformanceMonitoring.enable(
                config: .all(receiver: metricsConsumer),
                didCrashPreviously: didCrash,
                experiments: Experiments(dropStartupTimeWhenAppWasInBackground: startupBackgroundEnabled))
        } catch {
            preconditionFailure("Couldn't initialize PerformanceSuite: \(error)")
        }

        if didCrash {
            metricsConsumer.interop?.send(message: .crash)
        }
    }

    /// UI-test startup that boots through real Firebase Crashlytics, so tests can exercise the
    /// Crashlytics `previously-crashed` marker path (recovered-hang phantom crashes). The marker is
    /// the single source of truth here: if it is set on this launch, Crashlytics believes the
    /// previous run crashed, so we surface that as `.crash`.
    private func startWithCrashlyticsSupport(metricsConsumer: MetricsConsumer) {
        Self.configureFirebaseIfNeeded()
        let crashlytics = Crashlytics.crashlytics()
        let didCrash = crashlytics.didCrashDuringPreviousExecution()

        let reportingMode: CrashlyticsHangsReportingMode =
            ProcessInfo.processInfo.environment[crashlyticsHangsAsNonFatalsKey] != nil
            ? .fatalHangsAsNonFatals
            : .fatalHangsAsCrashes

        do {
            try PerformanceMonitoring.enableWithCrashlyticsSupport(
                config: .all(receiver: metricsConsumer),
                settings: CrashlyticsHangsSettings(reportingMode: reportingMode),
                crashlyticsEnabledInDebug: true)
        } catch {
            preconditionFailure("Couldn't initialize PerformanceSuite: \(error)")
        }

        if didCrash {
            metricsConsumer.interop?.send(message: .crash)
        }
    }

    private static func configureFirebaseIfNeeded() {
        guard FirebaseApp.app() == nil else { return }
        // Dummy options - we never talk to a real Firebase backend in UI tests; we only need
        // Crashlytics' on-device report/marker machinery.
        let options = FirebaseOptions(googleAppID: "1:11111111111:ios:aa1a1111111111a1", gcmSenderID: "123")
        options.projectID = "abc-xyz-123"
        options.apiKey = "A12345678901234567890123456789012345678"
        FirebaseApp.configure(options: options)
    }

    func makeMenuController() -> UIViewController {
        let menu = UINavigationController(rootViewController: RootController())
        return menu
    }

    func makeRenderingController() -> UIViewController {
        let view = RenderingUseCasesView()
        let hc = UIHostingController(rootView: view)
        hc.title = "Rendering"
        let nc = UINavigationController(rootViewController: hc)
        return nc
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
