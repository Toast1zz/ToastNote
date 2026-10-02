import Foundation

public enum VaultScanner {
    static let noteExtensions: Set<String> = ["md", "markdown"]

    public static func scan(root: URL) throws -> FolderNode {
        try scanFolder(at: root, relativePath: "", name: root.lastPathComponent)
    }

    private static func scanFolder(at url: URL, relativePath: String, name: String) throws -> FolderNode {
        let entries = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var folders: [FolderNode] = []
        var notes: [NoteRef] = []
        for entry in entries {
            let entryName = entry.lastPathComponent
            let childPath = relativePath.isEmpty ? entryName : relativePath + "/" + entryName
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                // An unreadable subfolder should not hide the rest of the vault.
                if let child = try? scanFolder(at: entry, relativePath: childPath, name: entryName) {
                    folders.append(child)
                }
            } else if noteExtensions.contains(entry.pathExtension.lowercased()) {
                notes.append(NoteRef(path: childPath, title: entry.deletingPathExtension().lastPathComponent))
            }
        }
        folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        notes.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return FolderNode(path: relativePath, name: name, folders: folders, notes: notes)
    }
}
