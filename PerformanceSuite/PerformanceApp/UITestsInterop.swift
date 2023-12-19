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

public enum Message: Codable, Equatable {
    case startupTime(duration: Int)
    case appFreezeTime(duration: Int)
    case freezeTime(duration: Int, screen: String)
    case tti(duration: Int, screen: String)
    case fragmentTTI(duration: Int, fragment: String)
    case fatalHang
    case nonFatalHang
    case watchdogTermination
    case memoryLeak
}

/// This is a namespace to access Client and Server classes
public enum UITestsInterop {

    /// Class is used to communicate between App target and UI Tests target.
    /// This part is a client part, which works in UI tests target.
    /// We start connection as a client and poll data from the server
    ///
    public class Client {

        public init() {
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

        public var messages: [Message] = []

        private func makeRequest() {
            let task = session.dataTask(with: url) { data, response, error in
                guard let data = data else {
                    // no data found
                    return
                }
                let messages = try! self.decoder.decode([Message].self, from: data)
                self.messages.append(contentsOf: messages)
            }
            task.resume()
        }

        public func reset() {
            messages = []
        }
    }


    /// Class is used to communicate between App target and UI Tests target.
    /// This part is a server part, which works in App target.
    /// We start server when app is started and send data to the open connection when needed.
    public final class Server {
        public init() {
            server = GCDWebServer()
            server.addDefaultHandler(forMethod: "GET", request: GCDWebServerRequest.self) { request in
                let messagesToSend = self.messages
                let data = try! self.encoder.encode(messagesToSend)
                self.messages = []
                return GCDWebServerDataResponse(data: data, contentType: "application/json")
            }
            try! server.start(options: [GCDWebServerOption_BindToLocalhost: true, GCDWebServerOption_Port: Client.port])
        }
        private let server: GCDWebServer
        private let encoder = JSONEncoder()
        private var messages: [Message] = []

        public func send(message: Message) {
            messages.append(message)
        }
    }

}
