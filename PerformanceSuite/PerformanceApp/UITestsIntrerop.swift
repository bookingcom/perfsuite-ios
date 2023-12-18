//
//  Interop.swift
//  PerformanceSuiteNew
//
//  Created by Gleb Tarasov on 09/03/2022.
//

import Foundation
import Network
import UIKit

public enum MetricType: Codable {
    case droppedFrames
    case tti
    case ttfr
}

public struct ScreenMetric: Codable {
    public init(type: MetricType, value: Int, screen: String) {
        self.type = type
        self.value = value
        self.screen = screen
    }

    public let type: MetricType
    public let value: Int
    public let screen: String
}


/// This is a namespace to access Client and Server classes
public enum UITestsInterop {

    /// Class is used to communicate between App target and UI Tests target.
    /// This part is a client part, which works in UI tests target.
    /// We start connection as a client and wait for data from the server.
    public class Client {

        public init() {}

        static let host: String = "localhost"
        static let port: UInt16 = 34340  // random value

        private let decoder = JSONDecoder()
        private let queue = DispatchQueue(label: "performance_suite.client")
        private var connection: NWConnection?

        public func receive<T: Decodable>(handler: @escaping (T) -> Void) {
            if connection == nil {
                startConnection()
            }

            connection?.receive(minimumIncompleteLength: 1, maximumLength: Int.max) { [weak self] content, _, _, error in
                // TCP message can be sent in several portions, but in the real life it is always sent in one portion, so we do not handle multiple portions for now
                if let error = error {
                    fatalError("Error in Client \(error)")
                } else if let content = content {
                    guard let value = try? self?.decoder.decode(T.self, from: content) else {
                        fatalError("Couldn't decode message")
                    }
                    handler(value)
                    // one message received, wait for the next message
                    self?.receive(handler: handler)
                } else {
                    // no error, but content is nil, this is a final message
                }
            }
        }

        private func startConnection() {
            guard let port = NWEndpoint.Port(rawValue: Self.port) else {
                fatalError("Wrong port value")
            }
            let connection = NWConnection(host: NWEndpoint.Host(Self.host), port: port, using: .tcp)
            connection.stateUpdateHandler = { state in
                switch state {
                    case .failed(let error):
                        fatalError("Client error \(error)")
                    default:
                        break
                }
            }

            connection.start(queue: queue)
            self.connection = connection
        }
    }


    /// Class is used to communicate between App target and UI Tests target.
    /// This part is a server part, which works in App target.
    /// We start server when app is started and send data to the open connection when needed.
    public final class Server {

        private let listener: NWListener
        private let queue = DispatchQueue(label: "performance_suite.server")
        private let encoder = JSONEncoder()
        private var connection: NWConnection?

        public init() {
            guard let port = NWEndpoint.Port(rawValue: Client.port) else {
                fatalError("Wrong port \(Client.port)")
            }
            guard let listener = try? NWListener(using: .tcp, on: port) else {
                fatalError("Cannot create listener")
            }
            self.listener = listener
            start()
        }

        private var isStarted: Bool {
            return
                listener.stateUpdateHandler != nil
        }

        private func start() {
            guard !isStarted else {
                fatalError("Server already started")
            }

            listener.stateUpdateHandler = { state in
                switch state {
                    case .failed(let error):
                        fatalError("Server error \(error)")
                    default:
                        break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                guard let self = self else { return }

                // we support only one connection
                precondition(self.connection == nil)
                self.connection = connection

                connection.stateUpdateHandler = { (state: NWConnection.State) in
                    debugPrint("newConnectionHandler state \(state)")
                    switch state {
                        case .waiting(let error):
                            fatalError("Server failed \(error)")
                        case .failed(let error):
                            fatalError("Server failed \(error)")
                        default:
                            break
                    }
                }
                connection.start(queue: self.queue)
            }
            listener.start(queue: .main)
        }

        public func send<T: Encodable>(value: T) {
            precondition(isStarted)
            precondition(connection != nil)
            guard let data = try? encoder.encode(value) else {
                fatalError("Couldn't encode \(value)")
            }
            connection?.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error = error {
                        fatalError("error in sending \(error)")
                    }
                })
        }
    }

}
