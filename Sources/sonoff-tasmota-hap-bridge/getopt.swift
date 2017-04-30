//
//  getopt.swift
//
import Foundation

/// Wrapper around getopt() / getopt_long_only() for Swift
///
/// - Parameters:
///   - options: String containing the option characters
///   - long: optional address of a `struct option` table for long options
///   - index: optional index for long option continuation
/// - Returns: the next option character, '?' in case of an error, `nil` if finished
func get(options: String, long: UnsafePointer<option>? = nil, index: UnsafeMutablePointer<CInt>? = nil) -> Character? {
    let argc = CommandLine.argc
    let argv = CommandLine.unsafeArgv
    let ch: CInt
    if long != nil {
        ch = getopt_long_only(argc, argv, options, long, index)
    } else {
        ch = getopt(argc, argv, options)
    }
    guard ch != -1, let u = UnicodeScalar(UInt32(ch)) else { return nil }
    let c = Character(u)
    return c
}
