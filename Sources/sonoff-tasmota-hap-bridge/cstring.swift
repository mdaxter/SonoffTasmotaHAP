//
//  cstring.swift
//

/// Perform a given function / closure with a mutable pointer to the given string.
/// This is a convenience method for C functions that take `char *` instead of
/// `const char *`.  Use with extreme care!
///
/// - Parameters:
///   - cString: C string to perform the given function on
///   - perform: function or closure to perform
/// - Returns: return value of the given template type `T` (can be `Void`)
func with<T>(cString: UnsafePointer<CChar>, perform: (UnsafeMutablePointer<CChar>) -> T) -> T {
    return perform(UnsafeMutablePointer(mutating: cString))
}
