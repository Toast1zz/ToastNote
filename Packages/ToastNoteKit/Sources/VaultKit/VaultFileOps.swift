import AppKit
import Foundation

public enum VaultFileOpsError: Error, Equatable {
    case alreadyExists(String)
    case invalidName
}

public struct VaultFileOps: Sendable {
    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func createNote(inFolder folder: String) throws -> NoteRef {
        let dir = url(for: folder)
        var title = "未命名"
        var n = 1
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(title + ".md").path) {
            n += 1
            title = "未命名 \(n)"
        }
        let path = Self.join(folder, title + ".md")
        try NoteFile.write("", to: root.appendingPathComponent(path))
        return NoteRef(path: path, title: title)
    }

    public func createFolder(named name: String, inFolder folder: String) throws -> String {
        let trimmed = try Self.validated(name)
        let path = Self.join(folder, trimmed)
        let target = root.appendingPathComponent(path)
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw VaultFileOpsError.alreadyExists(path)
        }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        return path
    }

    /// Renames a note or folder. Notes keep their extension; returns the new vault-relative path.
    public func rename(path: String, to newName: String) throws -> String {
        let trimmed = try Self.validated(newName)
        let source = root.appendingPathComponent(path)
        let ext = source.pathExtension
        let fileName = ext.isEmpty || isDirectory(source) ? trimmed : trimmed + "." + ext
        let parent = (path as NSString).deletingLastPathComponent
        let newPath = Self.join(parent, fileName)
        try moveItem(from: path, to: newPath)
        return newPath
    }

    public func move(path: String, toFolder folder: String) throws -> String {
        let newPath = Self.join(folder, (path as NSString).lastPathComponent)
        try moveItem(from: path, to: newPath)
        return newPath
    }

    /// Moves the item to the Trash. Never deletes permanently.
    public func trash(path: String) async throws {
        let url = root.appendingPathComponent(path)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.recycle([url]) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private func moveItem(from: String, to: String) throws {
        guard from != to else { return }
        let destination = root.appendingPathComponent(to)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw VaultFileOpsError.alreadyExists(to)
        }
        try FileManager.default.moveItem(at: root.appendingPathComponent(from), to: destination)
    }

    private func url(for folder: String) -> URL {
        folder.isEmpty ? root : root.appendingPathComponent(folder, isDirectory: true)
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private static func join(_ folder: String, _ name: String) -> String {
        folder.isEmpty ? name : folder + "/" + name
    }

    private static func validated(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.hasPrefix(".") else {
            throw VaultFileOpsError.invalidName
        }
        return trimmed
    }
}
