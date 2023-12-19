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
        // simulate long startup time
        Thread.sleep(forTimeInterval: 2)
        self.title = "Performance App"
    }

    @MainActor @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
