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

    let interop = UITestsHelper.isInTests ? UITestsInterop.Server() : nil

    func appRenderingMetricsReceived(metrics: RenderingMetrics) {
        log("App RenderingMetrics \(metrics)")
        interop?.send(message: Message.appFreezeTime(duration: metrics.freezeTime.milliseconds ?? -1))
    }

    func ttiMetricsReceived(metrics: TTIMetrics, screen: PerformanceScreen) {
        log("TTIMetrics \(screen) \(metrics)")
        interop?.send(message: Message.tti(duration: metrics.tti.milliseconds ?? -1, screen: screen.rawValue))
    }

    func renderingMetricsReceived(metrics: RenderingMetrics, screen: PerformanceScreen) {
        log("RenderingMetrics \(screen) \(metrics)")
        interop?.send(message: Message.freezeTime(duration: metrics.freezeTime.milliseconds ?? -1, screen: screen.rawValue))
    }

    func screenIdentifier(for viewController: UIViewController) -> PerformanceScreen? {
        return (viewController as? PerformanceTrackable)?.performanceScreen
    }

    func watchdogTerminationReceived(_ data: WatchdogTerminationData) {
        log("WatchdogTermination reported")
        interop?.send(message: Message.watchdogTermination)
    }

    func viewControllerLeakReceived(viewController: UIViewController) {
        log("View controller leak \(viewController)")
        interop?.send(message: Message.memoryLeak)
    }

    func startupTimeReceived(_ data: StartupTimeData) {
        log("Startup time received \(data.totalTime.milliseconds ?? 0) ms")
        interop?.send(message: Message.startupTime(duration: data.totalTime.milliseconds ?? -1))
    }

    func fragmentTTIMetricsReceived(metrics: TTIMetrics, fragment identifier: String) {
        log("fragmentTTIMetricsReceived \(identifier) \(metrics)")
        interop?.send(message: Message.fragmentTTI(duration: metrics.tti.milliseconds ?? -1, fragment: identifier))
    }

    func fatalHangReceived(info: HangInfo) {
        log("fatalHangReceived \(info)")
        interop?.send(message: Message.fatalHang)
    }

    func nonFatalHangReceived(info: HangInfo) {
        log("nonFatalHangReceived \(info)")
        interop?.send(message: Message.nonFatalHang)
    }

    func hangStarted(info: HangInfo) {
        log("hangStarted \(info)")
        interop?.send(message: Message.hangStarted)
    }

    var hangThreshold: TimeInterval {
        return 3
    }

    private func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }
    private let logger = Logger(subsystem: "com.booking.PerformanceApp", category: "MetricsConsumer")

    // MARK: - ViewControllerLoggingReceiver

    func onInit(screen: PerformanceScreen) {
        log("onInit \(screen)")
    }

    func onViewDidLoad(screen: PerformanceScreen) {
        log("onViewDidLoad \(screen)")
    }

    func onViewWillAppear(screen: PerformanceScreen) {
        log("onViewWillAppear \(screen)")
    }

    func onViewDidAppear(screen: PerformanceScreen) {
        log("onViewDidAppear \(screen)")
    }

    func onViewWillDisappear(screen: PerformanceScreen) {
        log("onViewWillDisappear \(screen)")
    }

    func onViewDidDisappear(screen: PerformanceScreen) {
        log("onViewDidDisappear \(screen)")
    }
}
