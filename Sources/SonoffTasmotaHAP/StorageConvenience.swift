//
//  StorageConvenience.swift
//  SonoffTasmotaHAP
//
import Foundation
import HAP

public extension Storage {
    /// String convenience subscript
    ///
    /// - Parameter key: dictionary key for associated `String` value
    public subscript(key: String) -> String? {
        get { return self[key].flatMap { String(data: $0, encoding: .utf8) } }
        set { self[key] = newValue.flatMap { $0.data(using: .utf8) } }
    }
    /// Boolean convenience subscript
    ///
    /// - Parameter key: dictionary key for associated `Bool` value
    public subscript(key: String) -> Bool? {
        get { return self[key].map { $0 != "0" } }
        set { self[key] = newValue.map { $0 ? "1" : "0" } }
    }
    /// Integer convenience subscript
    ///
    /// - Parameter key: dictionary key for associated `Int` value
    public subscript(key: String) -> Int? {
        get { return self[key].flatMap { Int($0) } }
        set { self[key] = newValue.map { "\($0)" } }
    }
    /// Double convenience subscript
    ///
    /// - Parameter key: dictionary key for associated `Double` value
    public subscript(key: String) -> Double? {
        get { return self[key].flatMap { Double($0) } }
        set { self[key] = newValue.map { "\($0)" } }
    }
}
