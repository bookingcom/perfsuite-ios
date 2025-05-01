import XCTest
import UIKit
import SwiftUI
@testable import PerformanceSuite

class TopScreenTests: XCTestCase {

    func testIsTopScreenWithNavigationParent() {
        let myController = MyViewController()
        let nav = UINavigationController(rootViewController: myController)
        XCTAssertTrue(isTopScreen(myController))
        XCTAssertFalse(isTopScreen(nav))
    }

    func testIsTopScreenWithNonContainerParent() {
        let parentController = MyViewController()
        let childController = MyViewController()
        parentController.addChild(childController)
        XCTAssertFalse(isTopScreen(childController))
        XCTAssertTrue(isTopScreen(parentController))
    }

    func testIsTopScreenWithCellSubview() {
        let cellSubviewController = MyViewController()
        let cellView = UITableViewCell()
        cellView.contentView.addSubview(cellSubviewController.view)
        XCTAssertFalse(isTopScreen(cellSubviewController))
    }

    func testIsTopScreenWithNavigationBarSubview() {
        let navBarSubviewController = MyViewController()
        let navBarView = UINavigationBar()
        navBarView.addSubview(navBarSubviewController.view)
        XCTAssertFalse(isTopScreen(navBarSubviewController))
    }

    func testIsTopScreenWithValidTopScreen() {
        let top = MyViewController()
        XCTAssertTrue(isTopScreen(top))
    }

    func testIsTopWithUIKitController() {
        let top = UIViewController()
        XCTAssertFalse(isTopScreen(top))
    }

    func testIsTopWithHostingController() {
        let view = MyViewForLastScreenObserverTests()
        let hosting = UIHostingController(rootView: view)
        XCTAssertTrue(isTopScreen(hosting))

        let nav = UINavigationController(rootViewController: hosting)
        XCTAssertTrue(isTopScreen(hosting))
    }
}

private class MyViewController: UIViewController { }
