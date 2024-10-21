//
//  Utils.swift
//  PerformanceSuiteTests
//
//  Created by Gleb Tarasov on 01/06/2023.
//

import UIKit

func makeWindow() -> UIWindow {
    let windowScene = UIApplication.shared
                    .connectedScenes
                    .filter { $0.activationState == .foregroundActive }
                    .first
    let window: UIWindow
    if let windowScene = windowScene as? UIWindowScene {
        // If host app supports scenes we should create a window connected to the active scene
        window = UIWindow(windowScene: windowScene)
    } else {
        // Otherwise just create a simple window
        window = UIWindow(frame: UIScreen.main.bounds)
    }
    return window
}
