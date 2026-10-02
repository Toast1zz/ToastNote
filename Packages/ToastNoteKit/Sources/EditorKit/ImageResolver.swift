import Foundation
import UniformTypeIdentifiers

/// What the editor needs to store a pasted or dropped image. VaultKit's `AttachmentStore` provides it; the
/// protocol keeps EditorKit independent of VaultKit (spec §4.4).
public protocol AttachmentSaving: Sendable {
    /// Saves image bytes and returns the vault-relative path to put into the note.
    func save(imageData: Data, uti: UTType, date: Date) throws -> String
    /// Copies an image file into the vault and returns its vault-relative path.
    func importFile(_ url: URL, date: Date) throws -> String
}

/// Finds the file behind an `![](source)` (spec §10.5).
public enum ImageResolver {
    /// Looks next to the note first, then from the vault root (the Obsidian habit). Remote URLs are not
    /// loaded in v1, and paths that would leave the vault are refused.
    public static func resolve(_ source: String, notePath: String, vaultRoot: URL) -> URL? {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("data:") { return nil }

        let candidates = [trimmed, trimmed.removingPercentEncoding].compactMap { $0 }
        let noteFolder = (notePath as NSString).deletingLastPathComponent
        let base = noteFolder.isEmpty ? vaultRoot : vaultRoot.appendingPathComponent(noteFolder, isDirectory: true)
        let root = vaultRoot.standardizedFileURL.resolvingSymlinksInPath().path

        for candidate in candidates {
            for directory in [base, vaultRoot] {
                let url = directory.appendingPathComponent(candidate).standardizedFileURL.resolvingSymlinksInPath()
                guard url.path.hasPrefix(root + "/"), FileManager.default.fileExists(atPath: url.path) else { continue }
                return directory.appendingPathComponent(candidate).standardizedFileURL
            }
        }
        return nil
    }
}
