//
//  Storage.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 25/01/2022.
//

import Foundation

/// Simple key-value storage, which is needed to a different services inside PerformanceSuite.
///
/// You can use `UserDefaults.standard`, which conforms to this protocol,
/// or replace it with something that is more common inside your app.
public protocol Storage {

    /// This method is called from the background thread, so reading should be synchronous.
    func read(domain: String, key: String) -> String?

    /// This method is called from the background thread and should perform writing synchronously ASAP,
    /// otherwise app might be terminated before writing is completed.
    func write(domain: String, key: String, value: String?)
}

public extension Storage {
    /// NB: Domain and key names should be unique across the project.
    /// So if you name enums the same - keys should be unique.
    func read<K, V>(key: K) -> V? where K: RawRepresentable, K.RawValue == String, V: LosslessStringConvertible {
        if let str = read(domain: String(describing: K.self), key: key.rawValue) {
            return V(str)
        } else {
            return nil
        }
    }

    func write<K, V>(key: K, value: V?) where K: RawRepresentable, K.RawValue == String, V: LosslessStringConvertible {
        write(domain: String(describing: K.self), key: key.rawValue, value: value?.description)
    }

    /// NB: Domain and key names should be unique across the project.
    /// So if you name enums the same - keys should be unique.
    func readJSON<K, V>(key: K) -> V? where K: RawRepresentable, K.RawValue == String, V: Decodable {
        if let str = read(domain: String(describing: K.self), key: key.rawValue),
            let data = str.data(using: .utf8) {
            return try? decoder.decode(V.self, from: data)
        } else {
            return nil
        }
    }

    func writeJSON<K, V>(key: K, value: V?) where K: RawRepresentable, K.RawValue == String, V: Encodable {
        if let value = value,
            let data = try? encoder.encode(value),
            let str = String(data: data, encoding: .utf8) {
            write(domain: String(describing: K.self), key: key.rawValue, value: str)
        } else {
            write(domain: String(describing: K.self), key: key.rawValue, value: nil)
        }
    }
}

private let encoder = JSONEncoder()
private let decoder = JSONDecoder()

extension UserDefaults: Storage {
    private func defaultsKey(domain: String, key: String) -> String {
        return domain + "." + key
    }

    public func read(domain: String, key: String) -> String? {
        return string(forKey: defaultsKey(domain: domain, key: key))
    }

    public func write(domain: String, key: String, value: String?) {
        set(value, forKey: defaultsKey(domain: domain, key: key))
    }
}
