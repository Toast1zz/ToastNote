import CoreServices
import Foundation

public enum VaultChange: Hashable, Sendable {
    case created(String)
    case modified(String)
    case removed(String)
    case renamed(from: String, to: String)
}

/// Watches a vault folder with FSEvents (no polling) and reports vault-relative changes.
public final class VaultWatcher: @unchecked Sendable {
    private let rootPath: String
    private let registry: SelfWriteRegistry
    private let onChange: @Sendable ([VaultChange]) -> Void
    private let queue = DispatchQueue(label: "app.toastnote.vault-watcher", qos: .utility)
    private var stream: FSEventStreamRef?
    /// Modification dates of self-writes already consumed, so the several events one atomic write
    /// produces across batches are all suppressed.
    private var consumedSelfWrites: [String: Date] = [:]

    public init(root: URL, registry: SelfWriteRegistry, onChange: @escaping @Sendable ([VaultChange]) -> Void) {
        // FSEvents reports real paths. Foundation's resolvingSymlinksInPath() leaves /var alone
        // (it special-cases it), so use realpath(3) to get /private/var.
        self.rootPath = Self.realPath(root.standardizedFileURL.path)
        self.registry = registry
        self.onChange = onChange
    }

    deinit { stop() }

    private static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    public func start() {
        queue.sync {
            guard stream == nil else { return }
            var context = FSEventStreamContext(
                version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil, release: nil, copyDescription: nil
            )
            let flags = UInt32(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
            )
            let callback: FSEventStreamCallback = { _, info, count, paths, flags, ids in
                guard let info else { return }
                let watcher = Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue()
                let cfPaths = unsafeBitCast(paths, to: CFArray.self) as? [String] ?? []
                var events: [RawEvent] = []
                for i in 0..<count where i < cfPaths.count {
                    events.append(RawEvent(path: cfPaths[i], flags: flags[i], id: ids[i]))
                }
                watcher.process(events)
            }
            guard let created = FSEventStreamCreate(
                nil, callback, &context, [rootPath] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags
            ) else { return }
            FSEventStreamSetDispatchQueue(created, queue)
            FSEventStreamStart(created)
            stream = created
        }
    }

    public func stop() {
        queue.sync {
            guard let current = stream else { return }
            FSEventStreamStop(current)
            FSEventStreamInvalidate(current)
            FSEventStreamRelease(current)
            stream = nil
        }
    }

    // MARK: - Event processing (runs on `queue`)

    struct RawEvent {
        var path: String
        var flags: FSEventStreamEventFlags
        var id: FSEventStreamEventId

        func has(_ flag: Int) -> Bool { flags & FSEventStreamEventFlags(flag) != 0 }
    }

    private func process(_ events: [RawEvent]) {
        var changes: [VaultChange] = []
        var index = 0
        while index < events.count {
            let event = events[index]
            guard let relative = relativePath(event.path), isRelevant(event, relative: relative) else {
                index += 1
                continue
            }
            if event.has(kFSEventStreamEventFlagItemRenamed) {
                let exists = FileManager.default.fileExists(atPath: event.path)
                // A rename is reported as two consecutive events: the old path (gone), then the new one.
                if !exists, index + 1 < events.count,
                   let next = Optional(events[index + 1]),
                   next.has(kFSEventStreamEventFlagItemRenamed),
                   next.id == event.id + 1,
                   FileManager.default.fileExists(atPath: next.path),
                   let nextRelative = relativePath(next.path), isRelevant(next, relative: nextRelative) {
                    changes.append(.renamed(from: relative, to: nextRelative))
                    index += 2
                    continue
                }
                changes.append(exists ? .created(relative) : .removed(relative))
            } else if event.has(kFSEventStreamEventFlagItemRemoved), !FileManager.default.fileExists(atPath: event.path) {
                changes.append(.removed(relative))
            } else if event.has(kFSEventStreamEventFlagItemCreated) {
                changes.append(.created(relative))
            } else if event.has(kFSEventStreamEventFlagItemModified) || event.has(kFSEventStreamEventFlagItemInodeMetaMod) {
                changes.append(.modified(relative))
            }
            index += 1
        }

        var seen = Set<VaultChange>()
        let filtered = changes.filter { change in
            guard seen.insert(change).inserted else { return false }
            return !isSelfWrite(change)
        }
        if !filtered.isEmpty { onChange(filtered) }
    }

    private func relativePath(_ path: String) -> String? {
        guard path.hasPrefix(rootPath + "/") else { return nil }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func isRelevant(_ event: RawEvent, relative: String) -> Bool {
        // Hidden files and folders (.git, .obsidian, .toastnote, atomic-write temp files) are never reported.
        if relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { return false }
        if event.has(kFSEventStreamEventFlagItemIsDir) { return true }
        let ext = (relative as NSString).pathExtension.lowercased()
        return VaultScanner.noteExtensions.contains(ext)
    }

    private func isSelfWrite(_ change: VaultChange) -> Bool {
        let path: String
        switch change {
        case .created(let p), .modified(let p): path = p
        default: return false
        }
        let url = URL(fileURLWithPath: rootPath).appendingPathComponent(path)
        guard let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        else { return false }
        if registry.isSelfWrite(path: path, modificationDate: mtime) {
            consumedSelfWrites[path] = mtime
            return true
        }
        if let consumed = consumedSelfWrites[path], abs(consumed.timeIntervalSince(mtime)) < 0.001 {
            return true
        }
        return false
    }
}
