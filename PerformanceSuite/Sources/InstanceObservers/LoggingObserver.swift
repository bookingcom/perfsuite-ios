//
//  LoggingObserver.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 23/09/2022.
//

import Foundation
import UIKit
import SwiftUI

/// Use this protocol for light-weight operations like logging only,
/// it is not intended to be used for some business-logic.
///
/// If you execute something heavy, offload it to some other background thread.
public protocol ViewControllerLoggingReceiver: ScreenMetricsReceiver {

    /// Method is called during view controller's initialization
    func onInit(screen: ScreenIdentifier)

    /// Method is called during view controller's `viewDidLoad`
    func onViewDidLoad(screen: ScreenIdentifier)

    /// Method is called during view controller's `viewWillAppear`
    func onViewWillAppear(screen: ScreenIdentifier)

    /// Method is called during view controller's `viewDidAppear`
    func onViewDidAppear(screen: ScreenIdentifier)

    /// Method is called during view controller's `viewWillDisappear`
    func onViewWillDisappear(screen: ScreenIdentifier)
}


/// Observer which forward all delegate methods to its receiver for logging purposes
final class LoggingObserver<V: ViewControllerLoggingReceiver>: ViewControllerInstanceObserver {

    init(screen: V.ScreenIdentifier, receiver: V) {
        self.screen = screen
        self.receiver = receiver
    }

    private let screen: V.ScreenIdentifier
    private let receiver: V

    func beforeInit() {
        PerformanceMonitoring.consumerQueue.async {
            self.receiver.onInit(screen: self.screen)
        }
    }

    func beforeViewDidLoad() {
        PerformanceMonitoring.consumerQueue.async {
            self.receiver.onViewDidLoad(screen: self.screen)
        }
    }

    func afterViewWillAppear() {
        PerformanceMonitoring.consumerQueue.async {
            self.receiver.onViewWillAppear(screen: self.screen)
        }
    }

    func afterViewDidAppear() {
        PerformanceMonitoring.consumerQueue.async {
            self.receiver.onViewDidAppear(screen: self.screen)
        }
    }

    func beforeViewWillDisappear() {
        PerformanceMonitoring.consumerQueue.async {
            self.receiver.onViewWillDisappear(screen: self.screen)
        }
    }

    static var identifier: AnyObject {
        return loggingObserverIdentifier
    }
}

private let loggingObserverIdentifier = NSObject()
