//
//  OutputViewController.swift
//  Pods
//
//  Created by Gleb Tarasov on 21/09/2024.
//
import UIKit
import XCTest

final class OutputViewController: UIViewController {

    var viewDisappeared: () -> Void = {}
    var viewAppeared: () -> Void = {}
    var output = ""

    init(outputTitle: String = "title") {
        self.outputTitle = outputTitle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    let outputTitle: String

    override func viewDidLoad() {
        super.viewDidLoad()
        output += "viewDidLoad\n"
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        output += "viewWillAppear\n"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        output += "viewDidAppear\n"
        viewAppeared()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        output += "viewWillDisappear\n"
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        output += "viewDidDisappear\n"

        viewDisappeared()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        output += "viewWillLayoutSubviews\n"
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        output += "viewDidLayoutSubviews\n"
    }

    deinit {
        XCTAssertTrue(Thread.isMainThread)
    }
}
