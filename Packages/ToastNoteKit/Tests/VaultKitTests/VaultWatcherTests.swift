import Foundation
import Testing
@testable import VaultKit

final class ChangeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [VaultChange] = []

    func add(_ changes: [VaultChange]) {
        lock.lock(); defer { lock.unlock() }
        storage.append(contentsOf: changes)
    }

    var changes: [VaultChange] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    /// Polls until `predicate` holds for the collected changes or `timeout` elapses.
    func wait(timeout: Duration = .seconds(3), until predicate: ([VaultChange]) -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if predicate(changes) { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return predicate(changes)
    }
}

private func startWatcher(
    root: URL, registry: SelfWriteRegistry = SelfWriteRegistry()
) async -> (VaultWatcher, ChangeCollector) {
    let collector = ChangeCollector()
    let watcher = VaultWatcher(root: root, registry: registry) { collector.add($0) }
    watcher.start()
    // Give the stream a moment to become live before the test touches files.
    try? await Task.sleep(for: .milliseconds(400))
    return (watcher, collector)
}

@Suite struct VaultWatcherTests {
    @Test func reportsExternalModification() async throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let (watcher, collector) = await startWatcher(root: root)
        defer { watcher.stop() }
        try touch(root, "a.md", "hello")
        let seen = await collector.wait { $0.contains(.modified("a.md")) || $0.contains(.created("a.md")) }
        #expect(seen)
    }

    @Test func ignoresSelfWrites() async throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = SelfWriteRegistry()
        let (watcher, collector) = await startWatcher(root: root, registry: registry)
        defer { watcher.stop() }
        let url = root.appendingPathComponent("a.md")
        try NoteFile.write("mine", to: url)
        let mtime = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
        registry.record(path: "a.md", modificationDate: mtime)
        try? await Task.sleep(for: .milliseconds(1500))
        #expect(collector.changes.isEmpty)
    }

    @Test func ignoresHiddenPaths() async throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let (watcher, collector) = await startWatcher(root: root)
        defer { watcher.stop() }
        try touch(root, ".toastnote/workspace.json", "{}")
        try? await Task.sleep(for: .milliseconds(1200))
        #expect(collector.changes.isEmpty)
    }

    @Test func pairsRenameEvents() async throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try touch(root, "a.md", "x")
        let (watcher, collector) = await startWatcher(root: root)
        defer { watcher.stop() }
        try FileManager.default.moveItem(at: root.appendingPathComponent("a.md"), to: root.appendingPathComponent("b.md"))
        let seen = await collector.wait { $0.contains(.renamed(from: "a.md", to: "b.md")) }
        #expect(seen)
    }
}
