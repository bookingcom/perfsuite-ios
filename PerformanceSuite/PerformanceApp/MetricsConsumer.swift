//
//  MetricsConsumer.swift
//  PerformanceApp
//
//  Created by Gleb Tarasov on 18/12/2023.
//

import Foundation
import OSLog
import PerformanceSuite
import SwiftUI

extension UIHostingController: PerformanceTrackable {
    var performanceScreen: PerformanceScreen? {
        return (introspectRootView() as? PerformanceTrackable)?.performanceScreen
    }
}

class MetricsConsumer: PerformanceSuiteMetricsReceiver {

    func appRenderingMetricsReceived(metrics: RenderingMetrics) {
        log("App RenderingMetrics \(metrics)")
    }

    func ttiMetricsReceived(metrics: TTIMetrics, viewController: UIViewController) {
        guard let screen = (viewController as? PerformanceTrackable)?.performanceScreen?.rawValue else {
            fatalError("unknown screen")
        }

        log("TTIMetrics \(screen) \(metrics)")
    }

    func renderingMetricsReceived(metrics: RenderingMetrics, viewController: UIViewController) {
        guard let screen = (viewController as? PerformanceTrackable)?.performanceScreen?.rawValue else {
            fatalError("unknown screen")
        }
        log("RenderingMetrics \(screen) \(metrics)")
    }

    func shouldTrack(viewController: UIViewController) -> Bool {
        return (viewController as? PerformanceTrackable)?.performanceScreen != nil
    }

    func watchdogTerminationReceived(_ data: WatchdogTerminationData) {
        log("WatchdogTermination reported")
    }

    func fatalHangReceived() {
        log("Fatal hang reported")
    }

    func nonFatalHangReceived(duration: DispatchTimeInterval) {
        log("Non-fatal hang reported with duration \(duration.seconds ?? 0)")
    }

    func startupFatalHangReceived() {
        log("Startup fatal hang reported")
    }

    func viewControllerLeakReceived(viewController: UIViewController) {
        log("View controller leak \(viewController)")
    }

    func startupTimeReceived(_ data: StartupTimeData) {
        log("Startup time received \(data.totalTime.milliseconds ?? 0) ms")
    }

    func fragmentTTIMetricsReceived(metrics: TTIMetrics, identifier: String) {
        log("fragmentTTIMetricsReceived \(identifier) \(metrics)")
    }

    func fatalHangReceived(info: HangInfo) {
        log("fatalHangReceived \(info)")
    }

    func nonFatalHangReceived(info: HangInfo) {
        log("nonFatalHangReceived \(info)")
    }

    func hangStarted(info: HangInfo) {
        log("hangStarted \(info)")
    }

    private func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }
    private let logger = Logger(subsystem: "com.booking.PerformanceApp", category: "MetricsConsumer")

    // MARK: - ViewControllerLoggingReceiver

    func key(for viewController: UIViewController) -> String {
        return String(describing: viewController)
    }

    func onInit(viewControllerKey: String) {
        log("onInit \(viewControllerKey)")
    }

    func onViewDidLoad(viewControllerKey: String) {
        log("onViewDidLoad \(viewControllerKey)")
    }

    func onViewWillAppear(viewControllerKey: String) {
        log("onViewWillAppear \(viewControllerKey)")
    }

    func onViewDidAppear(viewControllerKey: String) {
        log("onViewDidAppear \(viewControllerKey)")
    }

    func onViewWillDisappear(viewControllerKey: String) {
        log("onViewWillDisappear \(viewControllerKey)")
    }

    func onViewDidDisappear(viewControllerKey: String) {
        log("onViewDidDisappear \(viewControllerKey)")
    }
}
