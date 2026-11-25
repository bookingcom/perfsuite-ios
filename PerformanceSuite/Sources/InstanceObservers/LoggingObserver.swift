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
public protocol ViewControllerLoggingReceiver<ScreenIdentifier>: ScreenMetricsReceiver {

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
        self.screen = ReceiverIdentifier(screen)
        self.receiver = receiver
    }

    private let screen: ReceiverIdentifier<V.ScreenIdentifier>
    private let receiver: V

    func attach(viewController: UIViewController) {
        screen.viewController = viewController
    }

    func beforeInit() {
        PerformanceMonitoring.consumerQueue.async {
            self.screen.withIdentifier { self.receiver.onInit(screen: $0) }
        }
    }

    func beforeViewDidLoad() {
        PerformanceMonitoring.consumerQueue.async {
            self.screen.withIdentifier { self.receiver.onViewDidLoad(screen: $0) }
        }
    }

    func afterViewWillAppear() {
        PerformanceMonitoring.consumerQueue.async {
            self.screen.withIdentifier { self.receiver.onViewWillAppear(screen: $0) }
        }
    }

    func afterViewDidAppear() {
        PerformanceMonitoring.consumerQueue.async {
            self.screen.withIdentifier { self.receiver.onViewDidAppear(screen: $0) }
        }
    }

    func beforeViewWillDisappear() {
        PerformanceMonitoring.consumerQueue.async {
            self.screen.withIdentifier { self.receiver.onViewWillDisappear(screen: $0) }
        }
    }

    static var identifier: AnyObject {
        return loggingObserverIdentifier
    }
}

private let loggingObserverIdentifier = NSObject()
