//
//  RootView.swift
//  PerformanceApp
//
//  Created by Gleb Tarasov on 01/12/2021.
//

import SwiftUI

class RootController: UIHostingController<MenuView> {
    init() {
        super.init(rootView: MenuView())
        self.title = "Metrics"

        // simulate long startup time
        Thread.sleep(forTimeInterval: 2)
        
        // For UI tests: simulate a fatal hang during startup if requested
        if ProcessInfo.processInfo.environment[startupFatalHangKey] != nil {
            // Block the main thread indefinitely to simulate a fatal hang during startup
            Thread.sleep(forTimeInterval: .infinity)
        }
    }

    @MainActor @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
