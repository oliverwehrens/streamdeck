import Foundation

/// A value behind a lock. Portable stand-in for `OSAllocatedUnfairLock`, which exists only on Apple platforms.
public final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    public init(initialState: Value) {
        value = initialState
    }

    public func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
