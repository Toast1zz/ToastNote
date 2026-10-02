import Foundation

/// Pinned and open tabs plus the current one (spec §10.1). Pure value logic, so the rules are testable
/// without a window; the app keeps one of these and persists it through `WorkspaceFiles`.
public struct WorkspaceState: Equatable, Sendable {
    public var pinned: [String]
    public var open: [String]
    public var current: String?

    public init(pinned: [String] = [], open: [String] = [], current: String? = nil) {
        self.pinned = pinned
        self.open = open
        self.current = current
    }

    /// Tab cycling order: pinned notes first, then open ones.
    public var ordered: [String] { pinned + open }

    // MARK: Opening and closing

    /// Focuses the note if it is already a tab; otherwise adds it right after the current tab.
    public mutating func open(_ path: String) {
        if !ordered.contains(path) {
            if let current, let index = open.firstIndex(of: current) {
                open.insert(path, at: index + 1)
            } else {
                open.insert(path, at: 0)
            }
        }
        current = path
    }

    /// Closes an open tab and focuses its neighbor (next, else previous). Pinned notes cannot be closed.
    public mutating func close(_ path: String) {
        guard let index = open.firstIndex(of: path) else { return }
        open.remove(at: index)
        if current == path { current = neighbor(afterRemovingOpenAt: index) }
    }

    private func neighbor(afterRemovingOpenAt index: Int) -> String? {
        if index < open.count { return open[index] }
        if index > 0 { return open[index - 1] }
        return pinned.last
    }

    // MARK: Pinning

    public mutating func pin(_ path: String) {
        open.removeAll { $0 == path }
        if !pinned.contains(path) { pinned.append(path) }
    }

    /// An unpinned note becomes the first open tab.
    public mutating func unpin(_ path: String) {
        guard let index = pinned.firstIndex(of: path) else { return }
        pinned.remove(at: index)
        open.insert(path, at: 0)
    }

    /// Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`.
    public mutating func moveOpen(from offsets: IndexSet, to destination: Int) {
        let moving = offsets.filter { $0 < open.count }.map { open[$0] }
        let before = offsets.filter { $0 < destination }.count
        for index in offsets.sorted(by: >) where index < open.count { open.remove(at: index) }
        open.insert(contentsOf: moving, at: max(0, min(destination - before, open.count)))
    }

    // MARK: Selection

    public mutating func selectNext() { step(by: 1) }
    public mutating func selectPrevious() { step(by: -1) }

    private mutating func step(by delta: Int) {
        let tabs = ordered
        guard !tabs.isEmpty else { return }
        guard let current, let index = tabs.firstIndex(of: current) else {
            self.current = delta > 0 ? tabs.first : tabs.last
            return
        }
        self.current = tabs[(index + delta + tabs.count) % tabs.count]
    }

    /// 0-based index into `ordered`; out-of-range indices are ignored.
    public mutating func select(index: Int) {
        let tabs = ordered
        guard tabs.indices.contains(index) else { return }
        current = tabs[index]
    }

    // MARK: Vault changes

    /// Keeps tabs pointing at real files: renames move them, removals drop them (Review Focus 4).
    public mutating func apply(_ change: VaultChange) {
        switch change {
        case .renamed(let from, let to):
            pinned = pinned.map { Self.rewrite($0, from: from, to: to) }
            open = open.map { Self.rewrite($0, from: from, to: to) }
            current = current.map { Self.rewrite($0, from: from, to: to) }
        case .removed(let path):
            pinned.removeAll { Self.isAffected($0, by: path) }
            let removedCurrentIndex = current.flatMap { current in
                Self.isAffected(current, by: path) ? open.firstIndex(of: current) : nil
            }
            let currentRemoved = current.map { Self.isAffected($0, by: path) } ?? false
            var removedBeforeCurrent = 0
            for (index, tab) in open.enumerated() where Self.isAffected(tab, by: path) {
                if let removedCurrentIndex, index < removedCurrentIndex { removedBeforeCurrent += 1 }
            }
            open.removeAll { Self.isAffected($0, by: path) }
            if currentRemoved {
                let index = (removedCurrentIndex ?? 0) - removedBeforeCurrent
                current = open.isEmpty ? pinned.last : (index < open.count ? open[index] : open[open.count - 1])
            }
        case .created, .modified:
            break
        }
    }

    /// True when `path` is `target` itself or lives inside the folder `target`.
    private static func isAffected(_ path: String, by target: String) -> Bool {
        path == target || path.hasPrefix(target + "/")
    }

    private static func rewrite(_ path: String, from: String, to: String) -> String {
        if path == from { return to }
        if path.hasPrefix(from + "/") { return to + path.dropFirst(from.count) }
        return path
    }

    // MARK: Titles

    /// Path → tab title. Notes whose titles collide get " — 父文件夹" appended.
    public func displayTitles() -> [String: String] {
        func title(_ path: String) -> String {
            ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        }
        let counts = Dictionary(grouping: ordered, by: title).mapValues(\.count)
        var result: [String: String] = [:]
        for path in ordered {
            let base = title(path)
            if counts[base, default: 0] > 1 {
                let parent = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
                result[path] = parent.isEmpty ? base : "\(base) — \(parent)"
            } else {
                result[path] = base
            }
        }
        return result
    }
}
