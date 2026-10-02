import Foundation

/// Remembers writes made by the app itself so the file watcher can ignore the resulting events.
public final class SelfWriteRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: Date] = [:]

    public init() {}

    public func record(path: String, modificationDate: Date) {
        lock.lock()
        defer { lock.unlock() }
        entries[path] = modificationDate
    }

    /// Returns true once for a recorded write, then forgets it.
    public func isSelfWrite(path: String, modificationDate: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let recorded = entries[path],
              abs(recorded.timeIntervalSince(modificationDate)) < 0.001 else { return false }
        entries[path] = nil
        return true
    }
}
