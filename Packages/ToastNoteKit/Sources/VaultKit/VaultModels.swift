import Foundation

public struct NoteRef: Hashable, Sendable {
    /// Vault-relative, "/"-separated.
    public let path: String
    /// Filename without extension.
    public var title: String

    public init(path: String, title: String) {
        self.path = path
        self.title = title
    }
}

public struct FolderNode: Hashable, Sendable {
    /// "" for the vault root.
    public let path: String
    public let name: String
    public var folders: [FolderNode]
    public var notes: [NoteRef]

    public init(path: String, name: String, folders: [FolderNode] = [], notes: [NoteRef] = []) {
        self.path = path
        self.name = name
        self.folders = folders
        self.notes = notes
    }
}

public extension FolderNode {
    func allNotes() -> [NoteRef] {
        notes + folders.flatMap { $0.allNotes() }
    }
}
