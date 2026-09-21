//
//  Interop.swift
//  PerformanceSuiteNew
//
//  Created by Gleb Tarasov on 09/03/2022.
//

import Foundation
import Network
import UIKit
import GCDWebServer

public let inTestsKey = "UI_TESTS"
public let clearStorageKey = "CLEAR_STORAGE"
public let startupFatalHangKey = "STARTUP_FATAL_HANG"
/// When set, the app boots through `enableWithCrashlyticsSupport` (real Firebase Crashlytics)
/// instead of the lightweight custom crash interceptor, so UI tests can exercise the Crashlytics
/// `previously-crashed` marker path - e.g. the recovered-hang phantom-crash regression.
public let crashlyticsKey = "CRASHLYTICS"
/// When set (alongside `crashlyticsKey`), fatal hangs are reported as non-fatals
/// (`CrashlyticsHangsReportingMode.fatalHangsAsNonFatals`) instead of the default
/// `.fatalHangsAsCrashes`. Lets UI tests cover both hang reporting modes.
public let crashlyticsHangsAsNonFatalsKey = "CRASHLYTICS_HANGS_AS_NONFATALS"
/// Seconds to delay a simulated issue (crash/hang) after it is triggered. UI tests set this so
/// they can tap the trigger, send the app to the background, and have the issue happen *while
/// backgrounded*.
public let actionDelayKey = "ACTION_DELAY"
/// When set, the app *defers* the whole window/UI setup (so the first `viewDidAppear` happens a few
/// seconds after launch). This gives a UI test a deterministic window to send the app to the
/// background before startup finishes, exercising the "startup spanned a backgrounding → drop the
/// event" path.
public let startupBackgroundKey = "STARTUP_BACKGROUND"


/// Message which is sent from the app to UI tests target
public enum Message: Codable, Equatable {
    case startupTime(duration: Int)
    case appFreezeTime(duration: Int)
    case freezeTime(duration: Int, screen: String)
    case tti(duration: Int, screen: String)
    case fragmentTTI(duration: Int, fragment: String)
    case hangStarted
    case startupHangStarted
    case startupNonFatalHang
    case crashlyticsReady
    case fatalHang
    case startupFatalHang
    case nonFatalHang
    case watchdogTermination
    case memoryLeak
    case crash

    public static func == (lhs: Message, rhs: Message) -> Bool {
        switch (lhs, rhs) {
        case (.startupTime, .startupTime),
            (.appFreezeTime, .appFreezeTime),
            (.hangStarted, .hangStarted),
            (.startupHangStarted, .startupHangStarted),
            (.startupNonFatalHang, .startupNonFatalHang),
            (.crashlyticsReady, .crashlyticsReady),
            (.fatalHang, .fatalHang),
            (.startupFatalHang, .startupFatalHang),
            (.nonFatalHang, .nonFatalHang),
            (.watchdogTermination, .watchdogTermination),
            (.memoryLeak, .memoryLeak),
            (.crash, .crash):
            return true

        case let (.freezeTime(_, screenA), .freezeTime(_, screenB)),
            let (.tti(_, screenA), .tti(_, screenB)):
            return screenA == screenB

        case let (.fragmentTTI(_, fragmentA), .fragmentTTI(_, fragmentB)):
            return fragmentA == fragmentB

        default:
            return false
        }
    }
}

/// This is a namespace to access Client and Server classes
public enum UITestsInterop {

    // Keep events until the app exits. A dropped HTTP response must not consume them.
    // The session distinguishes a relaunched app from a repeated poll of the same events.
    struct MessageBatch: Codable {
        let session: UUID
        let messages: [Message]
    }

    struct MessageHistory {
        private var session: UUID?
        private var receivedCount = 0
        private(set) var messages: [Message] = []

        mutating func clearMessages() {
            messages.removeAll()
        }

        mutating func receive(_ batch: MessageBatch) {
            if session != batch.session {
                session = batch.session
                receivedCount = 0
            }
            guard batch.messages.count > receivedCount else { return }
            messages.append(contentsOf: batch.messages.dropFirst(receivedCount))
            receivedCount = batch.messages.count
        }
    }


    /// Class is used to communicate between App target and UI Tests target.
    /// This part is a client part, which works in UI tests target.
    /// We start connection as a client and poll data from the server
    ///
    public class Client {

        public init() {
            print("Client.init")
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.makeRequest()
            }
        }

        static let host: String = "localhost"
        static let port: UInt16 = 50001
        private let url = URL(string: "http://\(host):\(port)")!

        private let decoder = JSONDecoder()
        private let session: URLSession = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            return URLSession(configuration: configuration, delegate: nil, delegateQueue: .main)
        }()
        private var timer: Timer?
        private var task: URLSessionDataTask?
        private var isActive = true

        public var messages: [Message] {
            return messagesLock.withLock {
                history.messages
            }
        }

        private var history = MessageHistory()
        private let messagesLock = NSLock()

        private func makeRequest() {
            // Timer and completion both run on main. Never cancel an in-flight poll
            // just because the next timer tick arrived on a busy runner.
            guard isActive, task == nil else { return }
            print("Client.makeRequest")
            self.task = session.dataTask(with: url) { [weak self] data, _, _ in
                guard let self, self.isActive else { return }
                self.task = nil
                guard let data = data else {
                    print("No data found")
                    return
                }
                do {
                    let batch = try self.decoder.decode(MessageBatch.self, from: data)
                    let newMessages = self.messagesLock.withLock {
                        let previousCount = self.history.messages.count
                        self.history.receive(batch)
                        return Array(self.history.messages.dropFirst(previousCount))
                    }
                    if newMessages.isEmpty {
                        print("No new messages")
                    } else {
                        print("Messages received:\n--------------\n\(newMessages)\n--------------\n")
                    }
                } catch {
                    let str = String(data: data, encoding: .utf8)
                    fatalError("Couldn't decode messages from \(str ?? "empty")")
                }

            }
            self.task?.resume()
        }

        public func reset() {
            isActive = false
            timer?.invalidate()
            task?.cancel()
            task = nil
            session.invalidateAndCancel()
            messagesLock.withLock {
                history = MessageHistory()
            }
        }

        public func clearMessages() {
            messagesLock.withLock {
                history.clearMessages()
            }
        }
    }


    /// Class is used to communicate between App target and UI Tests target.
    /// This part is a server part, which works in App target.
    /// We start server when app is started and send data to the open connection when needed.
    ///
    /// We start server in the app, not in the UI tests target, because this way it will work on the device.
    /// The opposite way won't work on the real device. I will re-think if this is needed or not.
    /// If not, I will switch server and client back.
    public final class Server {
        public init() {
            server = GCDWebServer()
            server.addDefaultHandler(forMethod: "GET", request: GCDWebServerRequest.self) { _ in
                let messagesToSend = self.messagesLock.withLock {
                    MessageBatch(session: self.session, messages: self.messages)
                }
                do {
                    let data = try self.encoder.encode(messagesToSend)
                    return GCDWebServerDataResponse(data: data, contentType: "application/json")
                } catch {
                    fatalError("Couldn't encode messages \(messagesToSend)")
                }
            }
            do {
                try server.start(options: [GCDWebServerOption_BindToLocalhost: true, GCDWebServerOption_Port: Client.port])
            } catch {
                fatalError("Couldn't start GCDWebServer: \(error)")
            }
        }
        private let session = UUID()
        private let server: GCDWebServer
        private let encoder = JSONEncoder()

        private var messages: [Message] = []
        private let messagesLock = NSLock()

        public func send(message: Message) {
            messagesLock.withLock {
                self.messages.append(message)
            }
        }
    }

}
