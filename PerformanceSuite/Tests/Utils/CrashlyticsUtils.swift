//
//  CrashlyticsUtils.swift
//  Pods
//
//  Created by Gleb Tarasov on 21/09/2024.
//

import FirebaseCore
import FirebaseCrashlytics
import PerformanceSuite
import XCTest

func configureFirebase() {
    // we can configure it only once
    guard !firebaseConfigured else {
        return
    }
    let options = FirebaseOptions(googleAppID: "1:11111111111:ios:aa1a1111111111a1", gcmSenderID: "123")
    options.projectID = "abc-xyz-123"
    options.apiKey = "A12345678901234567890123456789012345678"
    FirebaseApp.configure(options: options)
    firebaseConfigured = true
}

private var firebaseConfigured = false
