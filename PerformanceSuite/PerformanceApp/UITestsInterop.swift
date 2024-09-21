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


/// Message which is sent from the app to UI tests target
public enum Message: Codable, Equatable {
    case startupTime(duration: Int)
    case appFreezeTime(duration: Int)
    case freezeTime(duration: Int, screen: String)
    case tti(duration: Int, screen: String)
    case fragmentTTI(duration: Int, fragment: String)
    case hangStarted
    case fatalHang
    case nonFatalHang
    case watchdogTermination
    case memoryLeak
    case crash

    public static func == (lhs: Message, rhs: Message) -> Bool {
        switch (lhs, rhs) {
        case (.startupTime, .startupTime),
            (.appFreezeTime, .appFreezeTime),
            (.hangStarted, .hangStarted),
            (.fatalHang, .fatalHang),
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
        private let session = URLSession(configuration: .default)
        private var timer: Timer?
        private var task: URLSessionDataTask?

        public var messages: [Message] {
            return messagesLock.withLock {
                messagesStorage
            }
        }

        private var messagesStorage: [Message] = []
        private let messagesLock = NSLock()

        private func makeRequest() {
            self.task?.cancel()

            print("Client.makeRequest")
            self.task = session.dataTask(with: url) { data, _, _ in
                guard let data = data else {
                    print("No data found")
                    return
                }
                do {
                    let messages = try self.decoder.decode([Message].self, from: data)
                    self.messagesLock.withLock {
                        self.messagesStorage.append(contentsOf: messages)
                    }
                    if messages.isEmpty {
                        print("No new messages")
                    } else {
                        print("Messages received:\n--------------\n\(messages)\n--------------\n")
                    }
                } catch {
                    let str = String(data: data, encoding: .utf8)
                    fatalError("Couldn't decode messages from \(str ?? "empty")")
                }

                self.task = nil
            }
            self.task?.resume()
        }

        public func reset() {
            messagesLock.withLock {
                messagesStorage.removeAll()
            }
            timer?.invalidate()
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
                    let result = self.messages
                    self.messages.removeAll()
                    return result
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
