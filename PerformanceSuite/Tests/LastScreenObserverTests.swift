//
//  LastScreenObserverTests.swift
//  Pods
//
//  Created by Gleb Tarasov on 19/10/2024.
//

import XCTest
import SwiftUI
import UIKit
@testable import PerformanceSuite

final class LastScreenObserverTests: XCTestCase {

    func testRuntimeInfoIsSaved() {
        AppInfoHolder.resetForTests()
        let vcs = [
            UIViewController(), // ignored, UIKit
            UIHostingController(rootView: MyViewForLastScreenObserverTests()), // take
            UINavigationController(rootViewController: UIViewController()), // ignored, UIKit
            MyViewController1(), // take
            UIPageViewController(), // ignored, container
            MyViewController2(), // ignored, container
            MyViewController3(rootView: MyView3()), // take

        ]
        _ = vcs.compactMap {
            let o = LastOpenedScreenObserver()
            o.afterViewDidAppear(viewController: $0)
            return o
        }

        let exp = expectation(description: "openedScreens")

        DispatchQueue.global().async {
            while AppInfoHolder.appRuntimeInfo.openedScreens.count < 3 {
                Thread.sleep(forTimeInterval: 0.001)
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 5)

        XCTAssertEqual(AppInfoHolder.appRuntimeInfo.openedScreens, [
            "MyViewForLastScreenObserverTests",
            "MyViewController1",
            "MyView3",
        ])
    }
}

private class MyViewController1: UIViewController { }
private class MyViewController2: UIPageViewController { }

private struct MyView3: View {
    var body: some View { return Text("blabla") }
}
private class MyViewController3: UIHostingController<MyView3> { }

// it shouldn't be private to have non-random type description
struct MyViewForLastScreenObserverTests: View {
    var body: some View { return Text("blabla") }
}
