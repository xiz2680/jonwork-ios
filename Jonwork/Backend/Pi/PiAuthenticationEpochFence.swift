import Foundation

/// Shared by the existing coordinator and credential providers. A Keychain write
/// and authorization replacement cannot interleave across different domains.
final class PiAuthenticationEpochFence: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    var current: UInt64 { lock.withLock { value } }
    func advance() -> UInt64 { lock.withLock { value &+= 1; return value } }
    func isCurrent(_ epoch: UInt64) -> Bool { lock.withLock { value == epoch } }
    func perform<T>(epoch: UInt64, _ action: () throws -> T) throws -> T {
        try lock.withLock {
            guard value == epoch else { throw CancellationError() }
            return try action()
        }
    }
}
