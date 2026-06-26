//
//  IssuesSimulator.swift
//  PerformanceApp
//
//  Created by Gleb Tarasov on 18/12/2023.
//

import Foundation

class IssuesSimulator {

    /// Optional delay (seconds) before a simulated issue actually happens. UI tests use it to send
    /// the app to the background first, so the crash/hang occurs while backgrounded.
    private static var actionDelay: TimeInterval {
        guard let raw = ProcessInfo.processInfo.environment[actionDelayKey],
              let value = TimeInterval(raw) else {
            return 0
        }
        return value
    }

    static func simulateNonFatalHang() {
        DispatchQueue.main.asyncAfter(deadline: .now() + actionDelay + 0.5) {
            Thread.sleep(forTimeInterval: 6)
        }
    }

    static func simulateFatalHang() {
        let lock = NSLock()
        DispatchQueue.global().asyncAfter(deadline: .now() + actionDelay + 0.5) {
            lock.lock()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                lock.lock()
            }
        }
    }

    static func simulateWatchdogTermination() {
        exit(0)
    }

    static func simulateCrash() {
        DispatchQueue.main.asyncAfter(deadline: .now() + actionDelay) {
            let a = 4
            let b = Int.random(in: 0...1) * (a - 4)
            let c = a / b
            print("Will not be executed \(c)")
        }
    }
}
